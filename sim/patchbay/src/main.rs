mod topology;
mod capture;
mod patchbay;

use anyhow::{ensure, Context, Result};
use std::path::PathBuf;

fn main() -> Result<()> {
    ::patchbay::init_userns().context(
        "Patchbay requires permitted Linux user namespaces; check AppArmor/container policy",
    )?;
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?
        .block_on(run())
}

async fn run() -> Result<()> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    ensure!(
        args.len() >= 4,
        "usage: runner <peer-binary> <tcp|udp|tcp-long> <source-dir> <artifacts-dir> [isp-script] [--nat-rules <file>] [--nat <peer=type>]..."
    );
    let binary = std::fs::canonicalize(&args[0])?;
    let test_kind = args[1].to_str().context("invalid test kind")?;
    ensure!(
        matches!(test_kind, "tcp" | "udp" | "tcp-long"),
        "unknown test kind"
    );
    let cwd = std::fs::canonicalize(&args[2])?;
    let artifacts = PathBuf::from(&args[3]);
    let mut isp_script = None;
    let mut nat_extra_rules = None;
    let mut nat_profiles = std::collections::BTreeMap::new();
    let mut optional = args[4..].iter();
    while let Some(arg) = optional.next() {
        if arg == "--nat-rules" {
            ensure!(nat_extra_rules.is_none(), "duplicate --nat-rules");
            let path = optional.next().context("--nat-rules requires a file")?;
            nat_extra_rules = Some(std::fs::read_to_string(path)?);
        } else if arg == "--nat" {
            let value = optional.next().context("--nat requires peer=type")?
                .to_str().context("invalid --nat value")?;
            let (peer, profile) = value.split_once('=').context("--nat requires peer=type")?;
            ensure!(matches!(peer, "peer_a" | "peer_b"), "unknown NAT peer: {peer}");
            let nat = match profile {
                "None" => ::patchbay::Nat::None,
                "Open" => ::patchbay::Nat::Open,
                "Moderate" => ::patchbay::Nat::Moderate,
                "Strict" => ::patchbay::Nat::Strict,
                _ => anyhow::bail!("unknown NAT type: {profile}"),
            };
            ensure!(nat_profiles.insert(peer.to_owned(), nat).is_none(), "duplicate NAT peer: {peer}");
        } else {
            ensure!(isp_script.is_none(), "unexpected runner argument");
            isp_script = Some(std::fs::canonicalize(arg)?);
        }
    }
    std::fs::create_dir_all(&artifacts)?;
    std::fs::write(artifacts.join("result.txt"), "RUNNING\n")?;
    let result = exercise(binary, cwd, &artifacts, test_kind, isp_script, nat_extra_rules, nat_profiles).await;
    std::fs::write(
        artifacts.join("result.txt"),
        match &result {
            Ok(()) => "PASS: verification and process exits succeeded\n".to_owned(),
            Err(e) => format!("FAIL: {e:#}\n"),
        },
    )?;
    result
}

async fn exercise(
    binary: PathBuf,
    cwd: PathBuf,
    artifacts: &std::path::Path,
    test_kind: &str,
    isp_script: Option<PathBuf>,
    nat_extra_rules: Option<String>,
    nat_profiles: std::collections::BTreeMap<String, ::patchbay::Nat>,
) -> Result<()> {
    let mut topology = topology::build(&topology::Program {
        binary: &binary,
        working_directory: &cwd,
        artifacts,
        tcp_tunnel: test_kind != "udp",
        isp_script: isp_script.as_deref(),
        nat_extra_rules: nat_extra_rules.as_deref(),
        nat_profiles: &nat_profiles,
    })
    .await?;
    let result = patchbay::verify(&mut topology, &binary, artifacts, test_kind).await;
    let cleanup = topology.stop_programs().await;
    result.and(cleanup)
}
