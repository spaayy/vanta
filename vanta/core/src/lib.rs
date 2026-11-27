//! Núcleo do Vanta Tools (F5a). Só lógica e tipos: nada de UI, rede, processo nem escrita em disco.
//! Todo I/O passa por traits ([`fs::Fs`], [`fs::FileWriter`], [`install::CommandRunner`],
//! [`tweaks::SystemStore`]) que o Vanta Tools liga depois.
//!
//! Convenção do kit (herdada do Vanta 1): em cada item do manifesto, `destino` é o caminho **dentro do kit**
//! (relativo à pasta do pacote) e `origem` é onde o item volta no Windows (com o perfil do PC antigo).

pub mod apps;
pub mod avancado;
pub mod catalog;
pub mod diario;
pub mod edicao;
pub mod energia;
pub mod extras;
pub mod fs;
pub mod guard;
pub mod install;
pub mod manifest;
pub mod niveis;
pub mod path;
pub mod restore;
pub mod servicos;
pub mod tweaks;
pub mod view;

#[cfg(test)]
mod testing;
