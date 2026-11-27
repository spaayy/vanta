//! Varre um kit real, só lendo: `cargo run --example scan_kit -- <pasta do kit>`.
//! Mostra o SHA-256 do manifesto, o resultado da guarda e o plano de restauração (nada é executado).

use vanta_core::fs::StdFs;
use vanta_core::guard::inspect;
use vanta_core::manifest::{PackageHealth, read, summarize};
use vanta_core::path::join;
use vanta_core::restore::{RestoreContext, RestoreOptions, Step, default_protected_roots, plan_restore};

fn main() {
    let kit = std::env::args().nth(1).expect("informe a pasta do kit");
    let summary = summarize(
        &StdFs,
        &[kit
            .trim_end_matches('\\')
            .trim_end_matches("pacote")
            .trim_end_matches('\\')
            .trim_end_matches("MeuPlaybook")
            .trim_end_matches('\\')
            .to_owned()],
    );
    println!(
        "pacote: {:?} {:?} ({} itens)",
        summary.health, summary.package_path, summary.configuration_count
    );
    if summary.health == PackageHealth::Missing {
        println!("localizador não achou; usando {kit} direto");
    }

    let loaded = match read(&StdFs, &join(&kit, "manifesto.json")) {
        Ok(loaded) => loaded,
        Err(error) => {
            println!("manifesto: {error}");
            std::process::exit(2);
        }
    };
    println!("manifesto: {} itens, sha256 {}", loaded.manifest.items.len(), loaded.sha256);

    let report = inspect(&StdFs, &kit, &loaded.manifest);
    println!("{report}");

    let ctx = RestoreContext {
        kit_root: kit,
        old_profile: r"C:\Users\Vanta".into(),
        current_profile: r"C:\Users\Novo".into(),
        is_elevated: false,
        protected_roots: default_protected_roots("C"),
    };
    let options = RestoreOptions { install_nvidia_driver: true, ..RestoreOptions::default() };
    let plan = plan_restore(&loaded.manifest, &ctx, &options);
    for step in &plan.steps {
        match step {
            Step::InstallPrograms => println!("passo: instalar programas"),
            Step::CloseApps { processes } => {
                println!("passo: fechar {} app(s): {}", processes.len(), processes.join(", "))
            }
            Step::CopyConfigs { items } => println!("passo: copiar {} item(ns) do usuário", items.len()),
            Step::InstallNvidiaDriver => println!("passo: instalar o driver NVIDIA"),
            Step::ElevatedBatch { items, remaps } => {
                println!(
                    "passo: LOTE ELEVADO com {} pasta(s): {}",
                    items.len(),
                    items.iter().map(|i| i.name.as_str()).collect::<Vec<_>>().join(", ")
                );
                for remap in remaps {
                    println!("       + remapear microfone em {}", remap.config_path);
                }
            }
            Step::CopyAfterDriver { items } => {
                println!("passo: copiar {} item(ns) depois do driver", items.len())
            }
            Step::RemapMicrophone { remaps } => println!("passo: remapear {} microfone(s)", remaps.len()),
        }
    }
    println!("pedidos de administrador no plano: {}", plan.elevated_batches());
    std::process::exit(i32::from(!report.is_clean()));
}
