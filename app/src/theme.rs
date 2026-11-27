//! Fluent design tokens for Windows 11, in Atlas blue.
//!
//! Every colour the UI paints comes from here. The values follow the WinUI 3
//! common resource dictionary (text, control, card, layer and subtle fills as
//! black/white at fixed opacities) so the app reads as native next to Settings,
//! with the brand blue standing in for the system accent. When a Windows
//! contrast theme is active the palette is built from the system colours
//! instead, and the Ease of Access text size and animation preferences are
//! carried here so every control can honour them.

use gpui::{App, Font, FontFeatures, FontStyle, FontWeight, Global, Hsla, Rgba, WindowAppearance, rgb};

use crate::i18n::Localization;
use crate::services::settings::ThemePreference;
use crate::services::system::{AccessibilityPreferences, SystemColors};

pub use crate::fonts::{FONT_DISPLAY, FONT_MONO, FONT_TEXT};
pub const FONT_ICONS: &str = "Segoe Fluent Icons";

/// [`FONT_TEXT`] with the current language's script fallbacks. Families set
/// lower down change only the family, so every element under whatever sets
/// this keeps the fallbacks: the window's root, and the content dialog, which
/// is drawn as a root of its own.
pub fn text_font(cx: &App) -> Font {
    Font {
        family: FONT_TEXT.into(),
        features: FontFeatures::default(),
        fallbacks: cx.global::<Localization>().font_fallbacks(),
        weight: FontWeight::NORMAL,
        style: FontStyle::Normal,
    }
}

/// Brand blue from the website and logo. Used for artwork; control fills use
/// a shade that keeps white text readable.
#[allow(dead_code)] // tema claro: só os testes usam; o Vanta é só escuro
pub const LIGHT_ACCENT: u32 = 0x1A91FF;
/// The light-mode accent fill: Atlas blue darkened until white text on it
/// clears the 4.5:1 contrast benchmark, as WinUI does with AccentDark1.
#[allow(dead_code)] // tema claro: só os testes usam; o Vanta é só escuro
pub const LIGHT_ACCENT_DARK1: u32 = 0x0A6BD4;
#[allow(dead_code)] // tema claro: só os testes usam; o Vanta é só escuro
pub const LIGHT_ACCENT_DARK2: u32 = 0x0862C2;
#[allow(dead_code)] // tema claro: só os testes usam; o Vanta é só escuro
pub const LIGHT_ACCENT_DARK3: u32 = 0x0759AF;
/// The dark-mode accent: lifted so near-black text sits on it.
#[allow(dead_code)] // tema claro: só os testes usam; o Vanta é só escuro
pub const LIGHT_ACCENT_LIGHT2: u32 = 0x5EB5FF;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Appearance {
    Light,
    Dark,
}

impl Appearance {
    pub fn from_window(appearance: WindowAppearance) -> Self {
        match appearance {
            WindowAppearance::Dark | WindowAppearance::VibrantDark => Appearance::Dark,
            WindowAppearance::Light | WindowAppearance::VibrantLight => Appearance::Light,
        }
    }

    pub fn is_dark(self) -> bool {
        matches!(self, Appearance::Dark)
    }
}

#[derive(Clone, Debug)]
pub struct Theme {
    pub appearance: Appearance,
    /// True when the window can show Mica: the app follows the system
    /// appearance, so DWM's tint matches the UI. Otherwise the root paints
    /// `solid_background` itself.
    pub mica: bool,
    /// A Windows contrast theme is active: system colours, no translucency.
    pub high_contrast: bool,
    /// "Show animations in Windows" is off: progress indicators hold still.
    pub reduce_motion: bool,
    /// The Ease of Access text size, applied through the window's rem size.
    pub text_scale: f32,

    /// The Vanta mark and other artwork.
    pub brand: Hsla,

    pub text_primary: Hsla,
    pub text_secondary: Hsla,
    pub text_tertiary: Hsla,
    pub text_disabled: Hsla,
    pub text_on_accent: Hsla,
    pub text_on_accent_disabled: Hsla,

    pub accent: Hsla,
    pub accent_hover: Hsla,
    pub accent_pressed: Hsla,
    pub accent_disabled: Hsla,
    pub accent_text: Hsla,
    pub accent_text_hover: Hsla,
    /// Fill and border of a selected card or option (identity tokens, F2).
    #[allow(dead_code)]
    pub accent_soft: Hsla,
    #[allow(dead_code)]
    pub accent_soft_stroke: Hsla,

    pub control_fill: Hsla,
    pub control_fill_hover: Hsla,
    pub control_fill_pressed: Hsla,
    pub control_fill_disabled: Hsla,
    /// A focused text box's fill (WinUI ControlFillColorInputActive).
    pub control_fill_input_active: Hsla,
    pub control_stroke: Hsla,
    pub control_stroke_secondary: Hsla,
    pub control_stroke_on_accent_secondary: Hsla,
    pub control_strong_stroke: Hsla,
    pub control_strong_stroke_disabled: Hsla,

    pub subtle_hover: Hsla,
    pub subtle_pressed: Hsla,

    pub card_fill: Hsla,
    pub card_stroke: Hsla,
    pub layer_fill: Hsla,
    pub layer_stroke: Hsla,
    pub solid_background: Hsla,
    pub divider: Hsla,
    /// Tooltips and flyouts: the solid colour WinUI's acrylic falls back to.
    pub flyout_fill: Hsla,
    pub flyout_stroke: Hsla,
    /// Behind a modal dialog, and the colour of the shadows under flyouts.
    #[allow(dead_code)]
    pub scrim: Hsla,
    #[allow(dead_code)]
    pub shadow: Hsla,

    pub focus_outer: Hsla,
    pub focus_inner: Hsla,

    pub success: Hsla,
    pub success_fill: Hsla,
    pub caution: Hsla,
    pub caution_fill: Hsla,
    pub critical: Hsla,
    pub critical_fill: Hsla,
    pub info: Hsla,
    pub info_fill: Hsla,
}

impl Global for Theme {}

fn c(hex: u32) -> Hsla {
    rgb(hex).into()
}

fn tint(rgb_hex: u32, alpha: f32) -> Hsla {
    let mut colour: Rgba = rgb(rgb_hex);
    colour.a = alpha;
    colour.into()
}

impl Theme {
    pub fn resolve(
        preference: ThemePreference,
        system: Appearance,
        accessibility: &AccessibilityPreferences,
    ) -> Theme {
        let mut theme = match accessibility.system_colors {
            Some(colors) if accessibility.high_contrast => Theme::high_contrast(colors),
            // Vanta is dark only and never uses Mica: the preference and the Windows theme don't change it.
            _ => {
                let _ = (preference, system);
                Theme::dark()
            }
        };
        theme.reduce_motion = accessibility.reduce_motion;
        theme.text_scale = accessibility.text_scale;
        theme
    }

    #[allow(dead_code)] // só os testes usam; o Vanta é só escuro
    pub fn light() -> Theme {
        Theme {
            appearance: Appearance::Light,
            mica: true,
            high_contrast: false,
            reduce_motion: false,
            text_scale: 1.0,

            brand: c(LIGHT_ACCENT),

            text_primary: tint(0x000000, 0.896),
            text_secondary: tint(0x000000, 0.606),
            text_tertiary: tint(0x000000, 0.446),
            text_disabled: tint(0x000000, 0.361),
            text_on_accent: c(0xFFFFFF),
            text_on_accent_disabled: c(0xFFFFFF),

            accent: c(LIGHT_ACCENT_DARK1),
            accent_hover: c(LIGHT_ACCENT_DARK2),
            accent_pressed: c(LIGHT_ACCENT_DARK3),
            accent_disabled: tint(0x000000, 0.217),
            accent_text: c(LIGHT_ACCENT_DARK1),
            accent_text_hover: c(0x0857AD),
            accent_soft: tint(0x000000, 0.0241),
            accent_soft_stroke: c(LIGHT_ACCENT_DARK1),

            control_fill: tint(0xFFFFFF, 0.7),
            control_fill_hover: tint(0xF9F9F9, 0.5),
            control_fill_pressed: tint(0xF9F9F9, 0.3),
            control_fill_disabled: tint(0xF9F9F9, 0.3),
            control_fill_input_active: c(0xFFFFFF),
            control_stroke: tint(0x000000, 0.0578),
            control_stroke_secondary: tint(0x000000, 0.1622),
            control_stroke_on_accent_secondary: tint(0x000000, 0.14),
            control_strong_stroke: tint(0x000000, 0.4458),
            control_strong_stroke_disabled: tint(0x000000, 0.2169),

            subtle_hover: tint(0x000000, 0.0373),
            subtle_pressed: tint(0x000000, 0.0241),

            card_fill: tint(0xFFFFFF, 0.7),
            card_stroke: tint(0x000000, 0.0578),
            layer_fill: tint(0xFFFFFF, 0.5),
            layer_stroke: tint(0x000000, 0.0578),
            solid_background: c(0xF3F3F3),
            divider: tint(0x000000, 0.0803),
            flyout_fill: c(0xF9F9F9),
            flyout_stroke: tint(0x000000, 0.0578),
            scrim: tint(0x000000, 0.4),
            shadow: tint(0x000000, 0.14),

            focus_outer: tint(0x000000, 0.896),
            focus_inner: c(0xFFFFFF),

            success: c(0x0F7B0F),
            success_fill: c(0xDFF6DD),
            caution: c(0x9D5D00),
            caution_fill: c(0xFFF4CE),
            critical: c(0xC42B1C),
            critical_fill: c(0xFDE7E9),
            info: c(0x0A6BD4),
            info_fill: tint(0xFFFFFF, 0.5),
        }
    }

    pub fn dark() -> Theme {
        Theme {
            appearance: Appearance::Dark,
            mica: false,
            high_contrast: false,
            reduce_motion: false,
            text_scale: 1.0,

            brand: c(0xB9A6FF),

            text_primary: c(0xF4F2FA),
            text_secondary: c(0xB4B0C6),
            text_tertiary: c(0x8E8A9F),
            text_disabled: c(0x5C586B),
            text_on_accent: c(0xFFFFFF),
            text_on_accent_disabled: c(0x6E6A7E),

            // Windows lifts the accent in dark mode so black text sits on it.
            accent: c(0x7349DB),
            accent_hover: c(0x7C52E6),
            accent_pressed: c(0x653DC7),
            accent_disabled: c(0x29253A),
            accent_text: c(0xA78BFA),
            accent_text_hover: c(0xC2B4FF),
            accent_soft: c(0x1F1933),
            accent_soft_stroke: c(0x7E62E3),

            control_fill: c(0x1B1824),
            control_fill_hover: c(0x221E2C),
            control_fill_pressed: c(0x181520),
            control_fill_disabled: c(0x131119),
            control_fill_input_active: c(0x0F0D15),
            control_stroke: c(0x2E2A3A),
            control_stroke_secondary: c(0x38334A),
            control_stroke_on_accent_secondary: c(0x5A3BB8),
            control_strong_stroke: c(0x7A7590),
            control_strong_stroke_disabled: c(0x3A3647),

            subtle_hover: c(0x16141E),
            subtle_pressed: c(0x121019),

            card_fill: c(0x15131C),
            card_stroke: c(0x26222F),
            layer_fill: c(0x100E16),
            layer_stroke: c(0x1E1B27),
            solid_background: c(0x0B0A10),
            divider: c(0x221F2B),
            flyout_fill: c(0x1D1A26),
            flyout_stroke: c(0x38334A),
            scrim: tint(0x000000, 0.70),
            shadow: tint(0x000000, 0.45),

            focus_outer: c(0xC2B4FF),
            focus_inner: c(0x0B0A10),

            success: c(0x4ADE80),
            success_fill: c(0x102117),
            caution: c(0xFBBF24),
            caution_fill: c(0x251D0C),
            critical: c(0xF87171),
            critical_fill: c(0x2A1316),
            info: c(0xA78BFA),
            info_fill: c(0x1A1628),
        }
    }

    /// A palette drawn entirely from the active Windows contrast theme, the
    /// way WinUI maps its brushes: window/window text for surfaces and body
    /// text, button face/text for controls, highlight for selection and the
    /// accent, hot light for links, gray text for disabled and tertiary text.
    /// Status colours collapse to text colour, so meaning is carried by the
    /// words and icons beside them. No translucency anywhere.
    pub fn high_contrast(colors: SystemColors) -> Theme {
        let window = c(colors.window);
        let text = c(colors.window_text);
        let button_face = c(colors.button_face);
        let button_text = c(colors.button_text);
        let highlight = c(colors.highlight);
        let highlight_text = c(colors.highlight_text);
        let gray = c(colors.gray_text);
        let link = c(colors.hot_light);
        let appearance = if relative_luminance(window) < 0.5 { Appearance::Dark } else { Appearance::Light };
        Theme {
            appearance,
            mica: false,
            high_contrast: true,
            reduce_motion: false,
            text_scale: 1.0,

            brand: text,

            text_primary: text,
            text_secondary: text,
            text_tertiary: gray,
            text_disabled: gray,
            text_on_accent: highlight_text,
            text_on_accent_disabled: gray,

            accent: highlight,
            accent_hover: highlight,
            accent_pressed: highlight,
            accent_disabled: button_face,
            accent_text: link,
            accent_text_hover: highlight,
            accent_soft: window,
            accent_soft_stroke: highlight,

            control_fill: button_face,
            control_fill_hover: highlight,
            control_fill_pressed: highlight,
            control_fill_disabled: button_face,
            control_fill_input_active: button_face,
            control_stroke: button_text,
            control_stroke_secondary: button_text,
            control_stroke_on_accent_secondary: button_text,
            control_strong_stroke: text,
            control_strong_stroke_disabled: gray,

            subtle_hover: highlight,
            subtle_pressed: highlight,

            card_fill: window,
            card_stroke: text,
            layer_fill: window,
            layer_stroke: text,
            solid_background: window,
            divider: text,
            flyout_fill: window,
            flyout_stroke: text,
            scrim: window,
            shadow: window,

            focus_outer: text,
            focus_inner: window,

            success: text,
            success_fill: window,
            caution: text,
            caution_fill: window,
            critical: text,
            critical_fill: window,
            info: text,
            info_fill: window,
        }
    }

    pub fn is_dark(&self) -> bool {
        self.appearance.is_dark()
    }

    /// Close button hover uses the same red on both appearances.
    pub fn caption_close_hover(&self) -> Hsla {
        if self.high_contrast { self.accent } else { c(0xC42B1C) }
    }

    /// The close glyph on [`Self::caption_close_hover`].
    pub fn caption_close_text(&self) -> Hsla {
        if self.high_contrast { self.text_on_accent } else { c(0xFFFFFF) }
    }

    /// Transparent, for elements that should let Mica through.
    pub fn transparent(&self) -> Hsla {
        Hsla::transparent_black()
    }

    /// Text colour for hovered controls: the high-contrast palette swaps to
    /// the highlight text colour whenever a highlight fill is used.
    pub fn text_on_hover(&self, normal: Hsla) -> Hsla {
        if self.high_contrast { self.text_on_accent } else { normal }
    }

    /// The fill behind selected text: the accent tinted, as Windows text
    /// boxes show it, or a contrast theme's highlight, opaque.
    pub fn selection_fill(&self) -> Hsla {
        if self.high_contrast { self.accent } else { self.accent.opacity(0.4) }
    }

    /// The colour selected text takes on [`Self::selection_fill`]: the
    /// highlight text colour in a contrast theme; elsewhere it keeps its own.
    pub fn selection_text(&self) -> Option<Hsla> {
        self.high_contrast.then_some(self.text_on_accent)
    }
}

/// WCAG relative luminance of an opaque colour.
fn relative_luminance(colour: Hsla) -> f32 {
    let rgba: Rgba = colour.into();
    fn channel(c: f32) -> f32 {
        if c <= 0.03928 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
    }
    0.2126 * channel(rgba.r) + 0.7152 * channel(rgba.g) + 0.0722 * channel(rgba.b)
}

/// Composites `over` onto an opaque `under`.
#[cfg(test)]
pub fn composite(over: Hsla, under: Hsla) -> Hsla {
    let top: Rgba = over.into();
    let bottom: Rgba = under.into();
    let a = top.a;
    Rgba {
        r: top.r * a + bottom.r * (1. - a),
        g: top.g * a + bottom.g * (1. - a),
        b: top.b * a + bottom.b * (1. - a),
        a: 1.,
    }
    .into()
}

/// WCAG contrast ratio between text and its background; both are composited
/// onto `backdrop` first so translucent tokens are judged as painted.
#[cfg(test)]
pub fn contrast_ratio(text: Hsla, background: Hsla, backdrop: Hsla) -> f32 {
    let background = composite(background, backdrop);
    let text = composite(text, background);
    let (a, b) = (relative_luminance(text), relative_luminance(background));
    let (light, dark) = if a > b { (a, b) } else { (b, a) };
    (light + 0.05) / (dark + 0.05)
}

/// The Windows 11 contrast themes, as `Ease of Access Themes\*.theme` define
/// them, for the tests of every control that draws in them.
#[cfg(test)]
pub(crate) fn windows_contrast_themes() -> [(&'static str, SystemColors); 4] {
    let theme =
        |window, window_text, button_face, button_text, highlight, highlight_text, gray, link| SystemColors {
            window,
            window_text,
            button_face,
            button_text,
            highlight,
            highlight_text,
            gray_text: gray,
            hot_light: link,
        };
    [
        ("Aquatic", theme(0x202020, 0xFFFFFF, 0x202020, 0xFFFFFF, 0x8EE3F0, 0x263B50, 0xA6A6A6, 0x75E9FC)),
        ("Desert", theme(0xFFFAEF, 0x3D3D3D, 0xFFFAEF, 0x202020, 0x903909, 0xFFF5E3, 0x676767, 0x1C5E75)),
        ("Dusk", theme(0x2D3236, 0xFFFFFF, 0x2D3236, 0xB6F6F0, 0xA1BFDE, 0x212D3B, 0xA6A6A6, 0x70EBDE)),
        ("Night sky", theme(0x000000, 0xFFFFFF, 0x000000, 0xFFEE32, 0xD6B4FD, 0x2B2B2B, 0xA6A6A6, 0x8080FF)),
    ]
}

pub trait ActiveTheme {
    fn theme(&self) -> &Theme;
}

impl ActiveTheme for App {
    fn theme(&self) -> &Theme {
        self.global::<Theme>()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const AA_NORMAL_TEXT: f32 = 4.5;

    fn assert_readable(name: &str, text: Hsla, background: Hsla, backdrop: Hsla) {
        let ratio = contrast_ratio(text, background, backdrop);
        assert!(ratio >= AA_NORMAL_TEXT, "{name}: {ratio:.2}:1 is below {AA_NORMAL_TEXT}:1");
    }

    // Disabled pairs are left out on purpose: WinUI's disabled tokens fall
    // below 4.5:1 by design, and WCAG exempts controls that can't be used.
    #[test]
    fn accent_buttons_keep_readable_labels_while_enabled() {
        for theme in [Theme::light(), Theme::dark()] {
            let name = format!("{:?}", theme.appearance);
            let layer = composite(theme.layer_fill, theme.solid_background);
            assert_readable(&format!("{name} accent"), theme.text_on_accent, theme.accent, layer);
            assert_readable(&format!("{name} accent hover"), theme.text_on_accent, theme.accent_hover, layer);
            assert_readable(
                &format!("{name} accent pressed"),
                theme.text_on_accent,
                theme.accent_pressed,
                layer,
            );
        }
    }

    #[test]
    fn light_and_dark_keep_text_readable_on_the_fill_it_sits_on() {
        for theme in [Theme::light(), Theme::dark()] {
            let name = format!("{:?}", theme.appearance);
            let backdrop = theme.solid_background;
            let layer = composite(theme.layer_fill, backdrop);
            assert_readable(&format!("{name} link"), theme.accent_text, theme.card_fill, layer);
            assert_readable(
                &format!("{name} link hover"),
                theme.accent_text_hover,
                theme.subtle_hover,
                layer,
            );
            assert_readable(&format!("{name} body"), theme.text_primary, theme.card_fill, layer);
            assert_readable(&format!("{name} secondary"), theme.text_secondary, theme.card_fill, layer);
            assert_readable(
                &format!("{name} secondary on the layer"),
                theme.text_secondary,
                theme.layer_fill,
                backdrop,
            );
            assert_readable(
                &format!("{name} standard button"),
                theme.text_primary,
                theme.control_fill,
                layer,
            );
            assert_readable(&format!("{name} flyout"), theme.text_primary, theme.flyout_fill, backdrop);
            assert_readable(&format!("{name} error caption"), theme.critical, theme.card_fill, layer);
        }
    }

    #[test]
    fn a_contrast_theme_uses_only_system_colours_and_no_translucency() {
        let colors = SystemColors {
            window: 0x000000,
            window_text: 0xFFFFFF,
            button_face: 0x000000,
            button_text: 0xFFFFFF,
            highlight: 0x1AEBFF,
            highlight_text: 0x000000,
            gray_text: 0x3FF23F,
            hot_light: 0xFFFF00,
        };
        let theme = Theme::resolve(
            ThemePreference::Light,
            Appearance::Light,
            &AccessibilityPreferences {
                high_contrast: true,
                reduce_motion: true,
                text_scale: 1.5,
                system_colors: Some(colors),
            },
        );
        assert!(theme.high_contrast);
        assert!(!theme.mica);
        assert!(theme.reduce_motion);
        assert_eq!(theme.text_scale, 1.5);
        assert_eq!(theme.appearance, Appearance::Dark, "follows the contrast theme, not the preference");
        for colour in
            [theme.card_fill, theme.layer_fill, theme.control_fill, theme.subtle_hover, theme.text_secondary]
        {
            assert_eq!(colour.a, 1.0, "high contrast never blends");
        }
        assert_eq!(theme.accent_text, c(0xFFFF00));
        assert_eq!(theme.text_on_accent, c(0x000000));
    }

    #[test]
    fn mica_shows_only_while_the_app_matches_the_system_appearance() {
        let accessibility = AccessibilityPreferences {
            high_contrast: false,
            reduce_motion: true,
            text_scale: 1.25,
            system_colors: None,
        };
        // Vanta is dark only and never shows Mica, whatever the preference or the Windows theme say.
        for system in [Appearance::Light, Appearance::Dark] {
            for preference in [ThemePreference::System, ThemePreference::Light, ThemePreference::Dark] {
                let theme = Theme::resolve(preference, system, &accessibility);
                let name = format!("{preference:?} on a {system:?} system");
                assert_eq!((theme.appearance, theme.mica), (Appearance::Dark, false), "{name}");
                assert!(!theme.high_contrast, "{name}");
                assert!(theme.reduce_motion, "{name}");
                assert_eq!(theme.text_scale, 1.25, "{name}");
            }
        }
        // A contrast theme whose colours couldn't be read keeps the usual palette.
        let unread = AccessibilityPreferences { high_contrast: true, ..accessibility };
        let theme = Theme::resolve(ThemePreference::Light, Appearance::Dark, &unread);
        assert_eq!((theme.appearance, theme.mica, theme.high_contrast), (Appearance::Dark, false, false));
    }

    #[test]
    fn contrast_themes_pair_text_with_the_fill_it_sits_on() {
        for (name, colors) in windows_contrast_themes() {
            let theme = Theme::high_contrast(colors);
            let window = theme.solid_background;
            let highlight = theme.subtle_hover;
            assert_readable(
                &format!("{name} hovered row"),
                theme.text_on_hover(theme.text_primary),
                highlight,
                window,
            );
            assert_readable(
                &format!("{name} selected gear"),
                theme.text_on_hover(theme.accent_text),
                highlight,
                window,
            );
            assert_readable(
                &format!("{name} hovered link"),
                theme.text_on_hover(theme.accent_text_hover),
                highlight,
                window,
            );
            assert_readable(&format!("{name} link"), theme.accent_text, theme.card_fill, window);
            // Why hovered rows must not keep their own text colour: window
            // text on the highlight fill is unreadable in every theme.
            assert!(contrast_ratio(theme.text_primary, highlight, window) < AA_NORMAL_TEXT, "{name}");
        }
    }

    #[test]
    fn contrast_themes_select_text_with_the_system_highlight_pair() {
        for (name, colors) in windows_contrast_themes() {
            let theme = Theme::high_contrast(colors);
            let field = theme.control_fill;
            let fill = theme.selection_fill();
            assert_eq!(fill.a, 1.0, "{name}: high contrast never blends");
            let text = theme.selection_text().expect(name);
            assert_readable(&format!("{name} selected text"), text, fill, field);
            // Non-text contrast: the selection stands out from the field.
            let ratio = contrast_ratio(fill, field, field);
            assert!(ratio >= 3.0, "{name}: the selection is {ratio:.2}:1 against the field");
        }
        for theme in [Theme::light(), Theme::dark()] {
            assert_eq!(theme.selection_text(), None, "selected text keeps its colour on the tint");
            assert!(theme.selection_fill().a < 1.0);
        }
    }

    #[test]
    fn contrast_ratio_matches_the_wcag_reference_values() {
        let ratio = contrast_ratio(c(0x000000), c(0xFFFFFF), c(0xFFFFFF));
        assert!((ratio - 21.0).abs() < 0.01);
        // #767676 is the lightest grey that clears AA on white.
        let ratio = contrast_ratio(c(0x767676), c(0xFFFFFF), c(0xFFFFFF));
        assert!((ratio - 4.54).abs() < 0.01, "{ratio}");
    }
}
