//! A paleta do Vanta 1 (App.xaml), aplicada só ao Vanta Tools. O Manager continua com `Theme::dark()`.
//! Painéis são translúcidos sobre a foto de fundo, como no Vanta 1.

use gpui::{Hsla, rgb, rgba};

use crate::theme::Theme;

fn c(hex: u32) -> Hsla {
    rgb(hex).into()
}

/// `0xRRGGBBAA`.
fn a(hex: u32) -> Hsla {
    rgba(hex).into()
}

pub const CANVAS: u32 = 0x0B0A10;
/// VSurface1: painel quase opaco, para a foto não atravessar o texto.
pub const SURFACE1: u32 = 0x131119DB;
pub const SURFACE2: u32 = 0x1B1824;
pub const SURFACE3: u32 = 0x221E2C;
pub const HAIRLINE: u32 = 0x26222F;
pub const HAIRLINE_STRONG: u32 = 0x38334A;
pub const INK: u32 = 0xF4F2FA;
pub const INK_MUTED: u32 = 0xB4B0C6;
pub const INK_SUBTLE: u32 = 0x8B8997;
pub const INK_FAINT: u32 = 0x6E6A7E;
pub const ACCENT: u32 = 0x7C4EE0;
pub const ACCENT_HOVER: u32 = 0x8B5CF6;
pub const ACCENT_PRESSED: u32 = 0x6D43D1;
pub const ACCENT_TEXT: u32 = 0xA78BFA;
pub const OK: u32 = 0x4ADE80;
pub const WARN: u32 = 0xFBBF24;
pub const ERR: u32 = 0xF87171;

/// Troca os campos do tema escuro pelos valores do Vanta 1. Alto contraste do Windows fica intocado.
pub fn apply_vanta1(theme: &mut Theme) {
    if theme.high_contrast {
        return;
    }
    theme.mica = false;
    theme.brand = c(ACCENT_TEXT);
    theme.solid_background = c(CANVAS);
    theme.card_fill = a(SURFACE1);
    theme.card_stroke = c(HAIRLINE);
    theme.layer_fill = a(SURFACE1);
    theme.layer_stroke = c(HAIRLINE);
    theme.flyout_fill = c(SURFACE3);
    theme.flyout_stroke = c(HAIRLINE_STRONG);
    theme.divider = c(HAIRLINE);
    theme.text_primary = c(INK);
    theme.text_secondary = c(INK_MUTED);
    theme.text_tertiary = c(INK_SUBTLE);
    theme.text_disabled = c(INK_FAINT);
    theme.text_on_accent = c(0xFFFFFF);
    theme.accent = c(ACCENT);
    theme.accent_hover = c(ACCENT_HOVER);
    theme.accent_pressed = c(ACCENT_PRESSED);
    theme.accent_text = c(ACCENT_TEXT);
    theme.accent_text_hover = c(0xC2B4FF);
    theme.accent_soft = a(0x7C4EE01A);
    theme.accent_soft_stroke = c(ACCENT);
    theme.control_fill = c(SURFACE2);
    theme.control_fill_hover = c(SURFACE3);
    theme.control_fill_pressed = c(SURFACE3);
    theme.control_fill_input_active = c(0x131119);
    theme.control_stroke = c(HAIRLINE_STRONG);
    theme.control_stroke_secondary = c(HAIRLINE_STRONG);
    theme.control_strong_stroke = c(INK_SUBTLE);
    theme.subtle_hover = a(0x1B1824B3);
    theme.subtle_pressed = c(SURFACE3);
    theme.focus_outer = c(0xA78BFE);
    theme.focus_inner = c(CANVAS);
    theme.success = c(OK);
    theme.caution = c(WARN);
    theme.critical = c(ERR);
    theme.info = c(ACCENT_TEXT);
}
