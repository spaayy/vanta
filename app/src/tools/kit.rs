//! As peças visuais do Vanta Tools, copiadas do Vanta 1 (App.xaml): imagens, tipografia, botões, toggle,
//! caixa, rádio, painel. Ficam aqui para o Manager manter os componentes Fluent dele sem mudança.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock};

use gpui::{
    Div, ElementId, FontWeight, Hsla, Image, ImageFormat, ParentElement, Role, SharedString, Stateful,
    Styled, Toggled, div, img, prelude::*, px, rgb, rgba,
};

use super::theme::*;
use crate::theme::{FONT_DISPLAY, FONT_ICONS, FONT_MONO, FONT_TEXT};
use crate::ui::focus_ring;

pub fn c(hex: u32) -> Hsla {
    rgb(hex).into()
}

/// `0xRRGGBBAA`.
pub fn a(hex: u32) -> Hsla {
    rgba(hex).into()
}

// ---------- imagens ----------

macro_rules! asset {
    ($path:literal) => {
        include_bytes!(concat!("../../assets/tools/", $path)).as_slice()
    };
}

/// Os 3 papéis de parede oficiais do Visual Vanta (2K assinados): (chave, nome, jpg).
pub const BACKGROUNDS: [(&str, &str, &[u8]); 3] = [
    ("eclipse", "Eclipse Violeta", asset!("bg/eclipse.jpg")),
    ("nebulosa", "Pico Nebulosa", asset!("bg/nebulosa.jpg")),
    ("torii", "Torii Névoa", asset!("bg/torii.jpg")),
];

const LOGOS: [(&str, &[u8]); 32] = [
    ("7zip", asset!("apps/7zip.png")),
    ("brave", asset!("apps/brave.png")),
    ("bun", asset!("apps/bun.png")),
    ("claude", asset!("apps/claude.png")),
    ("cloudflare", asset!("apps/cloudflare.png")),
    ("discord", asset!("apps/discord.png")),
    ("epicgames", asset!("apps/epicgames.png")),
    ("ffmpeg", asset!("apps/ffmpeg.png")),
    ("firefoxbrowser", asset!("apps/firefoxbrowser.png")),
    ("git", asset!("apps/git.png")),
    ("github", asset!("apps/github.png")),
    ("googlechrome", asset!("apps/googlechrome.png")),
    ("libreoffice", asset!("apps/libreoffice.png")),
    ("logitechg", asset!("apps/logitechg.png")),
    ("msi", asset!("apps/msi.png")),
    ("nodedotjs", asset!("apps/nodedotjs.png")),
    ("notepadplusplus", asset!("apps/notepadplusplus.png")),
    ("nvidia", asset!("apps/nvidia.png")),
    ("obsstudio", asset!("apps/obsstudio.png")),
    ("openjdk", asset!("apps/openjdk.png")),
    ("python", asset!("apps/python.png")),
    ("qbittorrent", asset!("apps/qbittorrent.png")),
    ("riotgames", asset!("apps/riotgames.png")),
    ("sharex", asset!("apps/sharex.png")),
    ("spotify", asset!("apps/spotify.png")),
    ("steam", asset!("apps/steam.png")),
    ("tailscale", asset!("apps/tailscale.png")),
    ("teamspeak", asset!("apps/teamspeak.png")),
    ("uv", asset!("apps/uv.png")),
    ("visualstudiocode", asset!("apps/visualstudiocode.png")),
    ("vlcmediaplayer", asset!("apps/vlcmediaplayer.png")),
    ("windowsterminal", asset!("apps/windowsterminal.png")),
];

/// Nome do programa no catálogo → logo (mesmo mapa do Vanta 1, `Catalogs.cs`).
fn logo_slug(name: &str) -> Option<&'static str> {
    Some(match name {
        "Brave" => "brave",
        "Google Chrome" => "googlechrome",
        "Mozilla Firefox" => "firefoxbrowser",
        "Steam" => "steam",
        "Riot Client" => "riotgames",
        "Epic Games Launcher" => "epicgames",
        "Discord" => "discord",
        "TeamSpeak 3" => "teamspeak",
        "Logitech G HUB" => "logitechg",
        "MSI Afterburner" => "msi",
        "OBS Studio" => "obsstudio",
        "VLC" => "vlcmediaplayer",
        "FFmpeg" => "ffmpeg",
        "Spotifast" | "Spotify (oficial)" => "spotify",
        "NanaZip" | "7-Zip" => "7zip",
        "ShareX" => "sharex",
        "qBittorrent" => "qbittorrent",
        "Notepad++" => "notepadplusplus",
        "LibreOffice" => "libreoffice",
        "Claude (desktop)" | "Claude Code" => "claude",
        "Windows Terminal" => "windowsterminal",
        "Git" => "git",
        "GitHub CLI" => "github",
        "Python 3.12" => "python",
        "uv" => "uv",
        "Node.js" => "nodedotjs",
        "Bun" => "bun",
        "Java 8" => "openjdk",
        "VS Code" => "visualstudiocode",
        "Tailscale" => "tailscale",
        "Cloudflare WARP" => "cloudflare",
        name if name.starts_with("NVCleanstall") => "nvidia",
        _ => return None,
    })
}

/// Cada imagem é decodificada uma vez e reaproveitada (o GPUI guarda a textura pelo id da imagem).
fn cached(key: &'static str, format: ImageFormat, bytes: &'static [u8]) -> Arc<Image> {
    static CACHE: OnceLock<std::sync::Mutex<HashMap<&'static str, Arc<Image>>>> = OnceLock::new();
    let mut map = CACHE.get_or_init(Default::default).lock().unwrap_or_else(|e| e.into_inner());
    map.entry(key).or_insert_with(|| Arc::new(Image::from_bytes(format, bytes.to_vec()))).clone()
}

pub fn background_image(key: &str) -> Arc<Image> {
    let (k, _, bytes) = BACKGROUNDS.iter().find(|(k, _, _)| *k == key).unwrap_or(&BACKGROUNDS[0]);
    cached(k, ImageFormat::Jpeg, bytes)
}

pub fn logo(name: &str, size: f32) -> Option<gpui::Img> {
    let slug = logo_slug(name)?;
    let (k, bytes) = LOGOS.iter().find(|(k, _)| *k == slug)?;
    Some(img(cached(k, ImageFormat::Png, bytes)).size(px(size)))
}

pub fn mark(size: f32) -> gpui::Img {
    img(cached("mark", ImageFormat::Png, asset!("mark.png"))).size(px(size))
}

// ---------- preferências (o mesmo arquivo do Vanta 1) ----------

#[derive(Clone)]
pub struct Prefs {
    pub background: String,
    pub dim: bool,
    pub selected_level: String,
    pub custom_tweaks: Option<Vec<String>>,
}

fn prefs_path() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("LOCALAPPDATA").unwrap_or_default())
        .join("Vanta")
        .join("preferencias.json")
}

impl Prefs {
    /// `%LOCALAPPDATA%\Vanta\preferencias.json`, o arquivo que o Vanta 1 já grava: quem trocou o fundo lá
    /// abre o Vanta 2 com o mesmo fundo, e a escolha de nível / estado "Personalizado" persiste ao reabrir.
    pub fn load() -> Self {
        let text = std::fs::read_to_string(prefs_path()).unwrap_or_default();
        Self::from_json_str(&text)
    }

    pub fn from_json_str(text: &str) -> Self {
        let value: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
        let background = value
            .get("Background")
            .and_then(|v| v.as_str())
            .filter(|k| BACKGROUNDS.iter().any(|(key, _, _)| key == k))
            .unwrap_or("eclipse")
            .to_owned();
        let dim = value.get("DimWorkPages").and_then(|v| v.as_bool()).unwrap_or(true);
        let selected_level = value
            .get("SelectedLevel")
            .and_then(|v| v.as_str())
            .filter(|id| vanta_core::niveis::Nivel::from_id(id).is_some())
            .unwrap_or("leve")
            .to_owned();
        let custom_tweaks = value.get("CustomTweaks").and_then(|v| v.as_array()).map(|arr| {
            arr.iter().filter_map(|item| item.as_str().map(str::to_owned)).collect::<Vec<String>>()
        });
        Self { background, dim, selected_level, custom_tweaks }
    }

    pub fn to_json_string(&self) -> String {
        let json = serde_json::json!({
            "Background": self.background,
            "DimWorkPages": self.dim,
            "SelectedLevel": self.selected_level,
            "CustomTweaks": self.custom_tweaks,
        });
        serde_json::to_string_pretty(&json).unwrap_or_default()
    }

    pub fn save(&self) {
        let path = prefs_path();
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(path, self.to_json_string());
    }
}

// ---------- textos simples dos ajustes (textos.json) ----------

#[derive(Clone, Default)]
pub struct TweakCopy {
    pub title: String,
    pub summary: String,
    pub explanation: String,
    pub gain: String,
    pub caution: String,
}

/// O `textos.json` traz, por ajuste, um objeto com título e explicações em linguagem simples (o Vanta 1 mostra
/// esses, não o título técnico do catálogo).
pub fn tweak_copy() -> HashMap<String, TweakCopy> {
    let value: serde_json::Value =
        serde_json::from_str(include_str!("../../assets/tools/textos.json")).unwrap_or_default();
    let text =
        |v: &serde_json::Value, key: &str| v.get(key).and_then(|s| s.as_str()).unwrap_or("").to_owned();
    value
        .get("ajustes")
        .and_then(|v| v.as_object())
        .map(|map| {
            map.iter()
                .map(|(id, v)| {
                    (
                        id.clone(),
                        TweakCopy {
                            title: text(v, "titulo"),
                            summary: text(v, "resumo"),
                            explanation: text(v, "explicacao"),
                            gain: text(v, "ganho"),
                            caution: text(v, "cuidado"),
                        },
                    )
                })
                .collect()
        })
        .unwrap_or_default()
}

/// A frase sob o título de cada área (Vanta 1, `Catalogs.cs`).
pub fn area_lead(category: &str) -> &'static str {
    match category {
        "Geral" => {
            "IA do Windows, telemetria, atualizações e o que roda escondido. Aqui você decide o que o Windows faz sem pedir."
        }
        "Interface" => {
            "Barra de tarefas, menu Iniciar, Explorador e tema. Muda o que você vê, não o desempenho."
        }
        "Windows" => "Notificações, Bluetooth, impressão, teclado e mouse. Desligue o que você não usa.",
        "Jogos" => "Como o Windows divide processador, placa de vídeo e timer enquanto você joga.",
        "Avancado" => "Rede, memória, disco e serviços. Cada item explica o custo antes de você mexer.",
        "Seguranca" => "Proteções do Windows. O isolamento de núcleo fica travado porque o Vanguard exige.",
        _ => "",
    }
}

/// Os glifos Segoe Fluent do Vanta 1 para cada área.
pub fn area_glyph(category: &str) -> &'static str {
    match category {
        "Geral" => "\u{EA18}",
        "Interface" => "\u{E790}",
        "Windows" => "\u{E7F4}",
        "Jogos" => "\u{E7FC}",
        "Avancado" => "\u{E9E9}",
        "Seguranca" => "\u{E72E}",
        _ => "\u{E713}",
    }
}

// ---------- tipografia ----------

pub fn glyph(code: &'static str, size: f32) -> Div {
    div().flex_shrink_0().font_family(FONT_ICONS).text_size(px(size)).line_height(px(size)).child(code)
}

/// VHeroTitle: Geist SemiBold 46/50.
pub fn hero(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_DISPLAY)
        .font_weight(FontWeight::SEMIBOLD)
        .text_size(px(46.))
        .line_height(px(50.))
        .text_color(c(INK))
        .child(text.into())
}

/// VPageTitle: Geist SemiBold 35/40.
pub fn page_title(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_DISPLAY)
        .font_weight(FontWeight::SEMIBOLD)
        .text_size(px(35.))
        .line_height(px(40.))
        .text_color(c(INK))
        .child(text.into())
}

/// VLead: Geist Regular 15/23, até 620 px.
pub fn lead(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_TEXT)
        .text_size(px(15.))
        .line_height(px(23.))
        .text_color(c(INK_MUTED))
        .max_w(px(620.))
        .child(text.into())
}

/// VSectionTitle: Geist SemiBold 16,8.
pub fn section_title(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::SEMIBOLD)
        .text_size(px(16.8))
        .line_height(px(24.))
        .text_color(c(INK))
        .child(text.into())
}

/// VRowTitle: Geist Medium 14,5.
pub fn row_title(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::MEDIUM)
        .text_size(px(14.5))
        .line_height(px(20.))
        .text_color(c(INK))
        .child(text.into())
}

/// VBody: Geist Regular 12,5/20.
pub fn body(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_TEXT)
        .text_size(px(12.5))
        .line_height(px(20.))
        .text_color(c(INK_SUBTLE))
        .child(text.into())
}

/// VCaption: Geist Medium 12.
pub fn caption(text: impl Into<SharedString>) -> Div {
    div()
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::MEDIUM)
        .text_size(px(12.))
        .line_height(px(16.))
        .text_color(c(INK_SUBTLE))
        .child(text.into())
}

/// VMono: Geist Mono 12.
pub fn mono(text: impl Into<SharedString>, size: f32) -> Div {
    div()
        .font_family(FONT_MONO)
        .text_size(px(size))
        .line_height(px(size + 6.))
        .text_color(c(INK_MUTED))
        .child(text.into())
}

/// VPanel: painel translúcido, raio 12.
pub fn panel() -> Div {
    div().w_full().min_w_0().bg(a(SURFACE1)).border_1().border_color(c(HAIRLINE)).rounded(px(12.))
}

/// VKeycap: tecla desenhada.
pub fn keycap(text: &'static str) -> Div {
    div()
        .min_w(px(20.))
        .px(px(6.))
        .py(px(1.))
        .flex()
        .justify_center()
        .bg(c(SURFACE2))
        .border_1()
        .border_b_2()
        .border_color(c(HAIRLINE_STRONG))
        .rounded(px(4.))
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::MEDIUM)
        .text_size(px(11.))
        .text_color(c(INK_SUBTLE))
        .child(text)
}

// ---------- controles ----------

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Primary,
    Secondary,
    Ghost,
}

/// VButtonBase + VPrimaryButton/VSecondaryButton/VGhostButton: 36 px, raio 8, Geist Medium 13,5.
/// Devolve o elemento sem clique: quem chama põe `.on_click`. Desabilitado não entra no Tab.
pub fn button(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    kind: Kind,
    glyph_code: Option<&'static str>,
    disabled: bool,
) -> Stateful<Div> {
    let label: SharedString = label.into();
    let (bg, border, fg, hover) = match kind {
        Kind::Primary => (c(ACCENT), a(0xFFFFFF33), c(0xFFFFFF), c(ACCENT_HOVER)),
        Kind::Secondary => (c(SURFACE2), c(HAIRLINE_STRONG), c(INK), c(SURFACE3)),
        Kind::Ghost => (a(0x00000000), a(0x00000000), c(INK_MUTED), a(0x1B1824CC)),
    };
    let pressed = match kind {
        Kind::Primary => c(ACCENT_PRESSED),
        _ => c(SURFACE3),
    };
    div()
        .id(id)
        .role(Role::Button)
        .aria_label(label.clone())
        .aria_disabled(disabled)
        .flex()
        .flex_shrink_0()
        .items_center()
        .justify_center()
        .gap(px(9.))
        .min_h(px(36.))
        .px(px(if kind == Kind::Primary { 18. } else { 14. }))
        .rounded(px(8.))
        .border_1()
        .border_color(border)
        .bg(bg)
        .text_color(fg)
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::MEDIUM)
        .text_size(px(13.5))
        .whitespace_nowrap()
        .when_some(glyph_code, |d, code| d.child(glyph(code, 14.)))
        .child(label)
        .map(|d| {
            if disabled {
                d.opacity(0.42)
            } else {
                d.cursor_pointer()
                    .tab_index(0)
                    .hover(move |s| {
                        let s = s.bg(hover);
                        if kind == Kind::Ghost { s.text_color(c(INK)) } else { s }
                    })
                    .active(move |s| s.bg(pressed))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
            }
        })
}

/// O toggle do Vanta 1: 40×20, ligado = roxo com a bola escura, desligado = contorno cinza.
pub fn toggle(
    id: impl Into<ElementId>,
    label: impl Into<SharedString>,
    on: bool,
    disabled: bool,
) -> Stateful<Div> {
    let knob = if on { c(CANVAS) } else { c(INK_MUTED) };
    div()
        .id(id)
        .role(Role::Switch)
        .aria_label(label.into())
        .aria_toggled(if on { Toggled::True } else { Toggled::False })
        .aria_disabled(disabled)
        .flex_shrink_0()
        .relative()
        .w(px(44.))
        .h(px(22.))
        .rounded(px(11.))
        .border_1()
        .border_color(if on { c(ACCENT) } else { c(INK_SUBTLE) })
        .bg(if on { c(ACCENT) } else { a(0x00000000) })
        .child(
            div()
                .absolute()
                .top(px(4.))
                .left(px(if on { 25. } else { 4. }))
                .size(px(12.))
                .rounded(px(6.))
                .bg(knob),
        )
        .map(|d| {
            if disabled {
                d.opacity(0.4)
            } else {
                d.cursor_pointer()
                    .tab_index(0)
                    .hover(move |s| {
                        if on {
                            s.bg(c(ACCENT_HOVER)).border_color(c(ACCENT_HOVER))
                        } else {
                            s.border_color(c(INK_MUTED))
                        }
                    })
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
            }
        })
}

/// A caixa quadrada do Vanta 1 (20 px, raio 6): vários por categoria.
pub fn check_box(on: bool, hover: bool) -> Div {
    div()
        .size(px(20.))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(6.))
        .border_1()
        .border_color(if on {
            c(ACCENT)
        } else if hover {
            c(INK_MUTED)
        } else {
            c(INK_SUBTLE)
        })
        .bg(if on { c(ACCENT) } else { a(0x00000000) })
        .text_color(c(0xFFFFFF))
        .when(on, |d| d.child(glyph("\u{E73E}", 11.)))
}

/// Rádio de 20 px: marcado = anel roxo com miolo branco.
pub fn radio_dot(on: bool) -> Div {
    div()
        .size(px(20.))
        .flex_shrink_0()
        .flex()
        .items_center()
        .justify_center()
        .rounded(px(10.))
        .border_1()
        .border_color(if on { c(ACCENT) } else { c(INK_SUBTLE) })
        .bg(if on { c(ACCENT) } else { a(0x00000000) })
        .when(on, |d| d.child(div().size(px(8.)).rounded(px(4.)).bg(c(0xFFFFFF))))
}

/// Barra fina de progresso (trilho hairline, preenchimento roxo).
pub fn meter(fraction: f32, width: Option<f32>) -> Div {
    let fraction = fraction.clamp(0., 1.);
    div()
        .h(px(4.))
        .rounded(px(2.))
        .bg(c(HAIRLINE))
        .map(|d| match width {
            Some(w) => d.w(px(w)),
            None => d.w_full(),
        })
        .child(div().h_full().rounded(px(2.)).bg(c(ACCENT)).w(gpui::relative(fraction)))
}

/// Selo de rodapé do cartão de programa: glifo + legenda.
pub fn badge(code: &'static str, text: impl Into<SharedString>) -> Div {
    div()
        .flex()
        .items_center()
        .gap(px(5.))
        .text_color(c(INK_SUBTLE))
        .child(glyph(code, 11.))
        .child(caption(text))
}

/// Link discreto no acento do Vanta: foco de teclado visível e área de clique confortável.
pub fn link(id: impl Into<ElementId>, label: impl Into<SharedString>, external: bool) -> Stateful<Div> {
    let label: SharedString = label.into();
    div()
        .id(id)
        .role(Role::Link)
        .aria_label(label.clone())
        .flex()
        .flex_shrink_0()
        .items_center()
        .gap(px(5.))
        .px(px(6.))
        .py(px(3.))
        .rounded(px(6.))
        .font_family(FONT_TEXT)
        .font_weight(FontWeight::MEDIUM)
        .text_size(px(12.5))
        .line_height(px(18.))
        .text_color(c(ACCENT_HOVER))
        .cursor_pointer()
        .tab_index(0)
        .hover(|s| s.bg(a(0x1B1824CC)).text_color(c(INK)))
        .active(|s| s.bg(c(SURFACE3)))
        .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
        .child(label)
        .when(external, |d| d.child(glyph("\u{E8A7}", 11.)))
}
