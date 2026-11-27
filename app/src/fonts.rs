//! Fontes do Vanta Manager e do Vanta Tools: o único ponto que escolhe famílias e arquivos.
//!
//! Usa Geist (Display em SemiBold; Text em Regular e Medium) e Geist Mono (Mono),
//! da Vercel, distribuídas sob a SIL Open Font License 1.1 (pp/licenses/fonts/Geist-OFL.txt).

use std::borrow::Cow;

pub const FONT_DISPLAY: &str = "Geist";
pub const FONT_TEXT: &str = "Geist";
pub const FONT_MONO: &str = "Geist Mono";

const FILES: &[&[u8]] = &[
    include_bytes!("../assets/fonts/Geist-Regular.ttf"),
    include_bytes!("../assets/fonts/Geist-Medium.ttf"),
    include_bytes!("../assets/fonts/Geist-SemiBold.ttf"),
    include_bytes!("../assets/fonts/GeistMono.ttf"),
];

/// The font files to register with GPUI at startup.
pub fn embedded() -> Vec<Cow<'static, [u8]>> {
    FILES.iter().map(|bytes| Cow::Borrowed(*bytes)).collect()
}

#[cfg(test)]
mod tests {
    #[test]
    fn every_embedded_font_is_a_real_font_file() {
        for bytes in super::embedded() {
            assert!(bytes.len() > 10_000 && matches!(&bytes[..4], [0, 1, 0, 0] | b"OTTO" | b"true"));
        }
    }
}
