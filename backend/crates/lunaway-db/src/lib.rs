//! Lunaway database access: the migrations and one repository module per
//! concern. Every query is checked at compile time against the schema
//! (`sqlx::query!`), with the offline cache in `backend/.sqlx/` for builds
//! without a database.

pub mod accounts;
pub mod community;
pub mod conflation;
pub mod content;
mod day_files;
pub mod deletions;
pub mod enforcement;
pub mod extcom;
pub mod fuel;
pub mod holds;
pub mod idempotency;
pub mod lists;
pub mod moderation;
pub mod municipalities;
pub mod packs;
pub mod place_tiles;
pub mod places;
pub mod pois;
pub mod records;
pub mod retention;
pub mod road_events;
pub mod routing;
pub mod search;
pub mod sources;
pub mod stats;
pub mod submissions;
pub mod summary;
pub mod takedown_journal;
pub mod takedowns;

use std::time::Duration;

use sqlx::{
    Postgres, Transaction,
    migrate::Migrator,
    postgres::{PgConnectOptions, PgPoolOptions},
};

pub use sqlx::PgPool;

/// The schema migrations, embedded in the binary.
pub static MIGRATOR: Migrator = sqlx::migrate!("../../migrations");

/// What can go wrong talking to the database.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum DbError {
    /// A query failed.
    #[error("database query failed")]
    Query(#[from] sqlx::Error),
    /// The migrations could not be applied.
    #[error("database migration failed")]
    Migrate(#[from] sqlx::migrate::MigrateError),
    /// An argument exceeds what a query accepts (a route shape too long to
    /// check in one corridor query).
    #[error("{what} exceeds {limit}")]
    TooLarge {
        /// What was too large.
        what: &'static str,
        /// The limit.
        limit: usize,
    },
    /// A stored value does not decode into its domain type: the schema's
    /// CHECK constraints should make this impossible, so it means the
    /// database was written by something else.
    #[error("stored {what} is invalid")]
    Decode {
        /// What was being read.
        what: &'static str,
        /// Why it does not decode.
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
}

impl DbError {
    /// Whether the database refused the rows themselves (a constraint
    /// they break, SQLSTATE class 23) rather than failing: the same rows
    /// would be refused again.
    #[must_use]
    pub fn is_constraint_violation(&self) -> bool {
        matches!(
            self,
            Self::Query(sqlx::Error::Database(d))
                if d.code().is_some_and(|c| c.starts_with("23"))
        )
    }

    pub(crate) fn decode(
        what: &'static str,
        source: impl std::error::Error + Send + Sync + 'static,
    ) -> Self {
        Self::Decode {
            what,
            source: Box::new(source),
        }
    }
}

/// How a pool connects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PoolConfig {
    /// Connections held at most.
    pub max_connections: u32,
    /// How long a caller waits for a free connection before failing.
    pub acquire_timeout: Duration,
    /// Server-side limit of one statement (`statement_timeout`), so a query
    /// abandoned by its caller does not keep running; none when `None`.
    pub statement_timeout: Option<Duration>,
}

impl PoolConfig {
    /// `max_connections`, a 10 s wait for a connection, no statement limit:
    /// what the command-line tools use.
    #[must_use]
    pub const fn new(max_connections: u32) -> Self {
        Self {
            max_connections,
            acquire_timeout: Duration::from_secs(10),
            statement_timeout: None,
        }
    }
}

/// A connection pool to `url`.
///
/// # Errors
///
/// [`DbError::Query`] when the server cannot be reached.
pub async fn connect(url: &str, max_connections: u32) -> Result<PgPool, DbError> {
    connect_with(url, PoolConfig::new(max_connections)).await
}

/// A connection pool to `url`, configured by `config`.
///
/// # Errors
///
/// [`DbError::Query`] when `url` does not parse or the server cannot be
/// reached.
pub async fn connect_with(url: &str, config: PoolConfig) -> Result<PgPool, DbError> {
    let mut options: PgConnectOptions = url.parse()?;
    if let Some(limit) = config.statement_timeout {
        options = options.options([("statement_timeout", format!("{}ms", limit.as_millis()))]);
    }
    Ok(PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(config.acquire_timeout)
        .connect_with(options)
        .await?)
}

/// Key of the advisory lock that serialises every writer of the catalogue
/// (`lunaway.conflation` in ASCII): the importers writing `source_records`
/// and the conflation writing `places`.
///
/// The change feed relies on it: with one writer of `places` at a time,
/// every committed `updated_seq` is below every value still in flight, so a
/// reader never skips a change. The importers take it too, so an import and a
/// conflation never lock the same records in opposite orders (a deadlock).
const WRITER_LOCK: i64 = 0x6c75_6e61_7761_7963;

/// Starts a transaction that holds the writers' lock until it ends; it waits
/// while another writer holds it, up to half an hour whatever the role's
/// `statement_timeout`: an import batch queued behind a conflation of the
/// whole country waits for it rather than failing. The transaction's own
/// statements keep the role's limit.
pub(crate) async fn begin_locked(pool: &PgPool) -> Result<Transaction<'static, Postgres>, DbError> {
    let mut tx = pool.begin().await?;
    sqlx::query!("SET LOCAL statement_timeout = '30min'")
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SELECT pg_advisory_xact_lock($1)", WRITER_LOCK)
        .execute(&mut *tx)
        .await?;
    sqlx::query!("SET LOCAL statement_timeout TO DEFAULT")
        .execute(&mut *tx)
        .await?;
    Ok(tx)
}

/// Applies the pending migrations.
///
/// # Errors
///
/// [`DbError::Migrate`] when a migration fails or a committed one was edited.
pub async fn migrate(pool: &PgPool) -> Result<(), DbError> {
    MIGRATOR.run(pool).await?;
    Ok(())
}
