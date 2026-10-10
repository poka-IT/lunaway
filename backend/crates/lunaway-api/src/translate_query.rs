//! `Query.translate`: a review or a description the app shows, translated
//! into the reader's language by Lunaway's translation server
//! (`crate::translate`) and kept, so each text is translated once.
//!
//! Only a stored text is translated, named by the item that holds it and
//! read under the rules of the screen that shows it: the API is no
//! translation service for texts of its own choosing.

use std::sync::Arc;

use async_graphql::{Context, Enum, Result, SimpleObject};
use chrono::Utc;
use lunaway_db::translations::{self, Original, Translatable};
use lunaway_domain::translation::{
    is_echo, is_target_language, primary_language, source_language, text_fingerprint,
};
use uuid::Uuid;

use crate::{
    client::ClientKey,
    error::{
        chain, internal, invalid_input, not_found, quota_spent, rate_limited_error, unavailable,
        unsupported_language,
    },
    quota::{Action, Subject},
    schema::{TranslateOnce, db, state},
    translate::TranslateError,
};

/// Longest source id a description is named by.
const MAX_SOURCE_CHARS: usize = 64;
/// Longest language tag a description is named by.
const MAX_LANG_CHARS: usize = 35;
/// How long a client is told to wait when the server is busy.
const BUSY_WAIT: std::time::Duration = std::time::Duration::from_secs(2);

/// What `Query.translate` translates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Enum)]
#[graphql(name = "TranslatableKind")]
pub enum GqlTranslatableKind {
    /// A review of Lunaway's community: `id` is `Review.id`.
    Review,
    /// A review of another source (the external community source,
    /// Mangrove): `id` is `ExternalReview.id`.
    ExternalReview,
    /// One of the place's own descriptions (`Place.descriptions`): `id` is
    /// the place's, `sourceId` and `lang` the description's.
    Description,
    /// A description of an open source (`Place.externalDescriptions`):
    /// `id` is the place's, `sourceId` and `lang` the description's.
    ExternalDescription,
}

/// A text in the language asked, made by Lunaway's own translation server
/// from open models: the app shows it marked as translated automatically,
/// with the original language, and the original one touch away.
#[derive(Debug, Clone, PartialEq, Eq, SimpleObject)]
pub struct Translation {
    /// The text in `targetLang`: the machine translation, or the original
    /// itself when it is in that language already (`engine` null).
    pub text: String,
    /// The language of the original (`de`): as its source or its author's
    /// app said, else guessed from its words.
    pub source_lang: String,
    /// The language asked.
    pub target_lang: String,
    /// The engine that translated it (`opus-mt`); null when the original
    /// was in `targetLang` already.
    pub engine: Option<String>,
    /// The model of the language pair, with its release; null likewise.
    pub model: Option<String>,
}

/// The item `kind` and `id` name, with a description's source and
/// language.
fn translatable(
    kind: GqlTranslatableKind,
    id: Uuid,
    source_id: Option<String>,
    lang: Option<String>,
) -> Result<Translatable> {
    let description = |source_id: Option<String>, lang: Option<String>| {
        let source = source_id
            .filter(|s| !s.is_empty() && s.chars().count() <= MAX_SOURCE_CHARS)
            .ok_or_else(|| invalid_input("a description is named by its sourceId"))?;
        let lang = lang
            .filter(|l| !l.is_empty() && l.chars().count() <= MAX_LANG_CHARS)
            .ok_or_else(|| invalid_input("a description is named by its lang"))?;
        Ok::<_, async_graphql::Error>((source, lang))
    };
    Ok(match kind {
        GqlTranslatableKind::Review => Translatable::Review(id),
        GqlTranslatableKind::ExternalReview => Translatable::ExternalReview(id),
        GqlTranslatableKind::Description => {
            let (source, lang) = description(source_id, lang)?;
            Translatable::Description {
                place: id,
                source,
                lang,
            }
        }
        GqlTranslatableKind::ExternalDescription => {
            let (source, lang) = description(source_id, lang)?;
            Translatable::ExternalDescription {
                place: id,
                source,
                lang,
            }
        }
    })
}

/// The translation of the item named into `target`: kept from an earlier
/// request while its original stands unchanged, else made now within the
/// client's quota and kept.
pub(crate) async fn translate(
    ctx: &Context<'_>,
    kind: GqlTranslatableKind,
    id: Uuid,
    source_id: Option<String>,
    lang: Option<String>,
    target: String,
) -> Result<Translation> {
    if !is_target_language(&target) {
        return Err(invalid_input("targetLang: two lower-case letters, as `fr`"));
    }
    if let Some(once) = ctx.data_opt::<TranslateOnce>()
        && once.0.swap(true, std::sync::atomic::Ordering::SeqCst)
    {
        return Err(invalid_input("one translate per request"));
    }
    let item = translatable(kind, id, source_id, lang)?;
    let original = {
        let (pool, _permit) = db(ctx).await?;
        translations::original(pool, &item)
            .await
            .map_err(|e| internal(&e))?
    }
    .ok_or_else(|| not_found("text to translate"))?;
    let Original { key, text, lang } = original;
    let (text, source_lang) = match lang.as_deref().and_then(primary_language) {
        Some(stored) => (text, Some(stored)),
        // A guess reads the text's first words: off the request's thread.
        None => tokio::task::spawn_blocking(move || {
            let found = source_language(None, &text);
            (text, found)
        })
        .await
        .map_err(|e| internal(&e))?,
    };
    let Some(source_lang) = source_lang else {
        return Err(unsupported_language(
            "the language of this text is not known",
        ));
    };
    if source_lang == target {
        return Ok(Translation {
            text,
            source_lang,
            target_lang: target,
            engine: None,
            model: None,
        });
    }
    let fingerprint = text_fingerprint(&text);
    let kept = {
        let (pool, _permit) = db(ctx).await?;
        translations::kept(pool, &key, &target)
            .await
            .map_err(|e| internal(&e))?
    };
    if let Some(kept) =
        kept.filter(|k| k.source_sha256 == fingerprint && k.source_lang == source_lang)
    {
        // A kept copy of the text is the verdict of an earlier request: no
        // model reads its language, and the model is not asked again.
        if is_echo(&text, &kept.text) {
            return Err(unsupported_language(
                "no translation between these two languages",
            ));
        }
        return Ok(Translation {
            text: kept.text,
            source_lang,
            target_lang: target,
            engine: Some(kept.engine),
            model: Some(kept.model),
        });
    }
    let st = state(ctx);
    if !st.translator.enabled() {
        return Err(unavailable("translation"));
    }
    // A request without a peer (a test without a socket; every request the
    // listener takes has one) is one more client, held to the same slots.
    let asker = ctx
        .data_opt::<ClientKey>()
        .copied()
        .unwrap_or(ClientKey::Unknown);
    let client = Subject::Client(asker);
    if let Err(wait) = st.quotas.take(Action::Translate, client) {
        return Err(quota_spent("translations", wait));
    }
    // The translation runs in a task of its own: a client that leaves does
    // not free the API's slot while the server still works on its text,
    // and the translation made is kept for the next reader. Only a
    // translation made counts: a refusal or a failure of the server gives
    // the use back, the wait for one of the client's slots too. What one
    // client makes the server do stays bounded by the slots of `Translator`
    // (four texts at once for all clients by default, half of them for one
    // client) and the server's own two and 14 s.
    let task = {
        let translator = Arc::clone(&st.translator);
        let quotas = Arc::clone(&st.quotas);
        let pool = st.pool.clone();
        let source_lang = source_lang.clone();
        let target = target.clone();
        tokio::spawn(async move {
            let made = match translator
                .translate(asker, &text, &source_lang, &target)
                .await
            {
                // The model gave the text back: it was not in the language
                // it was taken for, and no model reads it: kept below as the
                // verdict, so the model is not asked again, and counted, as
                // the model worked; never shown as a translation.
                Ok(made) => made,
                Err(error) => {
                    quotas.give_back(Action::Translate, client);
                    return Err(error);
                }
            };
            let echo = is_echo(&text, &made.text);
            let row = translations::Translation {
                text: made.text,
                source_lang,
                source_sha256: fingerprint.to_vec(),
                engine: made.engine,
                model: made.model,
                translated_at: Utc::now(),
            };
            // A translation that could not be kept costs a later request a
            // new one; this one still gets its answer.
            if let Err(error) = translations::keep(&pool, &key, &target, &row).await {
                tracing::warn!(error = %chain(&error), "a translation could not be kept");
            }
            if echo {
                return Err(TranslateError::Unsupported);
            }
            Ok(row)
        })
    };
    let row = match task.await {
        Ok(Ok(row)) => row,
        Ok(Err(error)) => {
            return Err(match error {
                TranslateError::Unsupported => {
                    unsupported_language("no translation between these two languages")
                }
                TranslateError::Busy
                | TranslateError::QueueFull(_)
                | TranslateError::ClientFull(_) => rate_limited_error(
                    "the translation server is busy; try again shortly",
                    BUSY_WAIT,
                ),
                TranslateError::Off => unavailable("translation"),
                error => {
                    // Which failure, never which text: the errors carry no
                    // body and no URL.
                    tracing::warn!(
                        error = %chain(&error), %source_lang, %target, "a translation failed"
                    );
                    unavailable("translation")
                }
            });
        }
        Err(error) => {
            // The task stopped without a translation: nothing was made.
            st.quotas.give_back(Action::Translate, client);
            return Err(internal(&error));
        }
    };
    Ok(Translation {
        text: row.text,
        source_lang: row.source_lang,
        target_lang: target,
        engine: Some(row.engine),
        model: Some(row.model),
    })
}
