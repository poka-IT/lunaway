///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsFr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsFr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.fr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <fr>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsFr _root = this; // ignore: unused_field

	@override 
	TranslationsFr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsFr(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$fr nav = _Translations$nav$fr._(_root);
	@override late final _Translations$map$fr map = _Translations$map$fr._(_root);
	@override late final _Translations$favorites$fr favorites = _Translations$favorites$fr._(_root);
	@override late final _Translations$profile$fr profile = _Translations$profile$fr._(_root);
	@override late final _Translations$locale$fr locale = _Translations$locale$fr._(_root);
}

// Path: nav
class _Translations$nav$fr extends Translations$nav$en {
	_Translations$nav$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get map => 'Carte';
	@override String get favorites => 'Favoris';
	@override String get profile => 'Profil';
}

// Path: map
class _Translations$map$fr extends Translations$map$en {
	_Translations$map$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get placeholder => 'La carte des emplacements pour camping-cars et vans arrive bientôt.';
}

// Path: favorites
class _Translations$favorites$fr extends Translations$favorites$en {
	_Translations$favorites$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get empty => 'Les lieux que vous enregistrez apparaîtront ici.';
}

// Path: profile
class _Translations$profile$fr extends Translations$profile$en {
	_Translations$profile$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get language => 'Langue';
	@override String get noAccountNeeded => 'Aucun compte n\'est nécessaire pour consulter. Contribuer ne demandera qu\'un geste.';
}

// Path: locale
class _Translations$locale$fr extends Translations$locale$en {
	_Translations$locale$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
}

/// The flat map containing all translations for locale <fr>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsFr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Carte',
			'nav.favorites' => 'Favoris',
			'nav.profile' => 'Profil',
			'map.placeholder' => 'La carte des emplacements pour camping-cars et vans arrive bientôt.',
			'favorites.empty' => 'Les lieux que vous enregistrez apparaîtront ici.',
			'profile.language' => 'Langue',
			'profile.noAccountNeeded' => 'Aucun compte n\'est nécessaire pour consulter. Contribuer ne demandera qu\'un geste.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			_ => null,
		};
	}
}
