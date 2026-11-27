//! Diz, para um kit real, o que o Restaurar aceita e o que recusa (e por quê): `.reg`, tarefas, início com o Windows e os
//! arquivos que iriam para o lote elevado. Só lê: `cargo run --example kit_report -- <pasta do kit>`.
//! Usa as mesmas funções do Restaurar (`execute::add_extras`, `restore_plan::hash_source`).

use std::path::Path;

use vanta_core::fs::StdFs;
use vanta_core::manifest::read;
use vanta_core::path::join;
use vanta_core::restore::{RestoreContext, RestoreOptions, Step, default_protected_roots, plan_restore};
use vanta_sys::execute::{RestoreSummary, add_extras, protected_dirs};
use vanta_sys::restore_batch::old_profile_from_origins;
use vanta_sys::restore_plan::{PlanItem, RestorePlan, destination_allowed, hash_source, validate_plan};

fn main() {
    let kit = std::env::args().nth(1).expect("informe a pasta do kit");
    let kit = kit.trim_end_matches('\\').to_owned();
    let loaded = match read(&StdFs, &join(&kit, "manifesto.json")) {
        Ok(loaded) => loaded,
        Err(error) => {
            println!("manifesto: {error}");
            std::process::exit(2);
        }
    };
    let manifest = &loaded.manifest;
    let origins: Vec<String> = manifest.items.iter().map(|i| i.restore_path.clone()).collect();
    let old = old_profile_from_origins(&origins).unwrap_or_default();
    let current = std::env::var("USERPROFILE").unwrap_or_default();
    let ctx = RestoreContext {
        kit_root: kit.clone(),
        old_profile: old,
        current_profile: current,
        is_elevated: false,
        protected_roots: default_protected_roots("C"),
    };
    let steps = plan_restore(manifest, &ctx, &RestoreOptions::default());
    let mut plan = RestorePlan::default();
    let mut summary = RestoreSummary::default();
    for step in &steps.steps {
        let (Step::CopyConfigs { items }
        | Step::CopyAfterDriver { items }
        | Step::ElevatedBatch { items, .. }) = step
        else {
            continue;
        };
        let elevated = matches!(step, Step::ElevatedBatch { .. });
        for item in items {
            plan.allowed_destinations.push(item.destination.clone());
            if item.is_folder {
                plan.restored_roots.push(item.destination.clone());
            }
            if elevated {
                match hash_source(Path::new(&item.source), item.is_folder) {
                    Ok(files) => plan.items.push(PlanItem {
                        name: item.name.clone(),
                        source: item.source.clone(),
                        destination: item.destination.clone(),
                        is_folder: item.is_folder,
                        files,
                    }),
                    Err(error) => summary.failures.push(format!("{}: origem ilegível ({error})", item.name)),
                }
            }
        }
    }
    plan.protected_dirs = protected_dirs(&plan.items);
    println!(
        "itens do manifesto: {} | rejeitados no plano: {} | cópias elevadas: {} ({} arquivo(s) com SHA-256)",
        manifest.items.len(),
        steps.rejected.len(),
        plan.items.len(),
        plan.items.iter().map(|i| i.files.len()).sum::<usize>()
    );
    for (name, error) in &steps.rejected {
        println!("  REJEITADO NO PLANO: {name}: {error}");
    }
    for item in &plan.items {
        let allowed = destination_allowed(&item.destination, &plan.allowed_destinations);
        println!(
            "  elevado: {} -> {} [{}] ({} arquivo(s))",
            item.name,
            item.destination,
            if allowed { "destino permitido" } else { "DESTINO RECUSADO" },
            item.files.len()
        );
    }
    println!("pastas protegidas pedidas: {:?}", plan.protected_dirs);

    add_extras(manifest, &ctx, &mut plan, &mut summary);

    println!("\n== Registro (.reg)");
    for reg in &plan.registry {
        println!("  PASSA     {}", reg.label);
    }
    println!("\n== Tarefas e início com o Windows");
    for task in &plan.tasks {
        println!(
            "  PASSA     tarefa {}{}",
            task.name,
            if task.scripts.is_empty() {
                String::new()
            } else {
                format!(
                    "  (script com hash: {})",
                    task.scripts.iter().map(|s| s.path.as_str()).collect::<Vec<_>>().join(", ")
                )
            }
        );
    }
    for run in &plan.runs {
        println!("  PASSA     Run {} = {}", run.name, run.command);
    }
    println!("\n== Recusado ou avisado");
    for failure in &summary.failures {
        println!("  RECUSADO  {failure}");
    }
    for warning in &summary.warnings {
        println!("  AVISO     {warning}");
    }
    let program_data = std::env::var("ProgramData").unwrap_or_else(|_| r"C:\ProgramData".into());
    match validate_plan(&plan, &program_data) {
        Ok(()) => println!("\nplano inteiro: válido"),
        Err(why) => println!("\nplano inteiro: RECUSADO ({why})"),
    }
    println!(
        "resumo: {} registro(s), {} tarefa(s), {} entrada(s) de início; {} recusado(s), {} aviso(s)",
        plan.registry.len(),
        plan.tasks.len(),
        plan.runs.len(),
        summary.failures.len(),
        summary.warnings.len()
    );
}
