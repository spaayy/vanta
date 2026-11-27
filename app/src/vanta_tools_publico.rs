//! Vanta Tools, edição pública (amigos): sem Restaurar, sem as configurações do Nathan e sem programas que vêm do
//! pacote. É o mesmo código do `VantaTools`; só a edição muda (`tools::run(Edicao::Publica)`).
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
    tools::run(Edicao::Publica);
}
