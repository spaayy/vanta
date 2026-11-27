//! Vanta Tools: programas, restauração do kit e ajustes do Windows. Mesmo pacote do Manager: os módulos de tema,
//! fontes e componentes são os mesmos (montados aqui, não copiados). O que só o Tools usa fica em `tools/`.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
// O Tools monta toda a árvore do Manager porque `theme` e `ui` dependem dela; o que ele não usa o linker descarta.
#![allow(dead_code, unused_imports, unused_macros)]

#[cfg(not(windows))]
compile_error!("Vanta Tools builds only for Windows.");

mod assets;
mod cli;
mod environment;
mod flow;
mod fonts;
mod i18n;
mod model;
mod pages;
mod platform;
mod services;
mod shell;
mod theme;
mod tools;
mod ui;

use crate::tools::Edicao;

fn main() {
    tools::run(Edicao::Pessoal);
}
