//! `lunaway packs`: the regional first-sync packs (`docs/region-packs.md`).

use std::path::PathBuf;

use anyhow::Context;
use clap::Subcommand;
use lunaway_api::packs::PackOptions;
use lunaway_db::PgPool;

#[derive(Subcommand)]
pub(crate) enum Packs {
    /// Builds the pack of every sync region from one snapshot of the
    /// places, records it for `Query.regions`, and removes the files of the
    /// packs before the previous one. Run after each import and its
    /// conflation.
    Build {
        /// The directory the backend serves under `/packs/`.
        #[arg(long, env = "LUNAWAY_PACKS_DIR")]
        dir: PathBuf,
        /// Only this region (`FR-BRE`, `ES`); repeat for several.
        #[arg(long = "region")]
        only: Vec<String>,
        /// After a place was taken down: rebuilds the regions named even if
        /// nothing changed, and every region whose pack is behind, and
        /// removes every pack file the manifest does not name. A region
        /// left without a live place loses its pack and its files.
        #[arg(long, requires = "only")]
        takedown: bool,
    },
    /// Prints the packs recorded.
    List,
}

pub(crate) async fn run(pool: &PgPool, action: Packs) -> anyhow::Result<()> {
    match action {
        Packs::Build {
            dir,
            only,
            takedown,
        } => {
            let options = PackOptions {
                dir,
                only,
                takedown,
            };
            let report =
                lunaway_api::packs::build(pool, lunaway_api::ApiConfig::from_env(), &options)
                    .await
                    .context("pack build failed")?;
            println!("region       places      bytes        raw  file");
            for b in &report.built {
                println!(
                    "{:<10} {:>8} {:>10} {:>10}  {}",
                    b.pack.region, b.pack.places, b.pack.bytes, b.pack.raw_bytes, b.pack.file
                );
                for old in &b.removed {
                    println!("  removed {old}");
                }
            }
            for d in &report.dropped {
                println!("{:<10} no live place: pack withdrawn", d.region);
                for old in &d.removed {
                    println!("  removed {old}");
                }
            }
            for old in &report.pruned {
                println!("previous file removed: {old}");
            }
        }
        Packs::List => {
            let packs = lunaway_db::packs::all(pool).await?;
            println!("region       places      bytes  seq        generated            file");
            for p in &packs {
                println!(
                    "{:<10} {:>8} {:>10}  {:<10} {}  {}",
                    p.region, p.places, p.bytes, p.seq, p.generated_at, p.file
                );
            }
        }
    }
    Ok(())
}
