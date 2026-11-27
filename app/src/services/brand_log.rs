//! Replaces cosmetic Atlas branding in log lines with Vanta while preserving
//! real system paths, registry keys, PowerShell identifiers and package names.

/// Replaces cosmetic `Atlas` / `AtlasOS` / `[AtlasProgress]` branding with
/// `Vanta` / `[VantaProgress]`, leaving real filesystem paths, registry keys,
/// module/cmdlet names, CBS package names and `Atlas Setup Recovery` intact.
pub fn sanitize_brand(text: &str) -> String {
    if !text.contains("Atlas") && !text.contains("atlas") {
        return text.to_owned();
    }

    let bytes = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;

    while i < bytes.len() {
        // [AtlasProgress] -> [VantaProgress]
        if text[i..].starts_with("[AtlasProgress]") {
            out.push_str("[VantaProgress]");
            i += "[AtlasProgress]".len();
            continue;
        }

        // Match standalone "AtlasOS Toolbox", "AtlasOS", or "Atlas"
        if text[i..].starts_with("Atlas") {
            let prev = if i == 0 { None } else { Some(bytes[i - 1]) };
            if !is_protected_before(prev) {
                // Keep real folder name "Atlas Setup Recovery"
                if text[i..].starts_with("Atlas Setup Recovery") {
                    out.push_str("Atlas Setup Recovery");
                    i += "Atlas Setup Recovery".len();
                    continue;
                }
                // "AtlasOS Toolbox" -> "Vanta Toolbox"
                if text[i..].starts_with("AtlasOS Toolbox")
                    && !is_protected_after(bytes, i + "AtlasOS Toolbox".len())
                {
                    out.push_str("Vanta Toolbox");
                    i += "AtlasOS Toolbox".len();
                    continue;
                }
                // Standalone "AtlasOS" -> "Vanta"
                if text[i..].starts_with("AtlasOS")
                    && !is_protected_after(bytes, i + "AtlasOS".len())
                {
                    out.push_str("Vanta");
                    i += "AtlasOS".len();
                    continue;
                }
                // Standalone "Atlas" (including "[Atlas]" and "Atlas's") -> "Vanta"
                if !is_protected_after(bytes, i + "Atlas".len()) {
                    out.push_str("Vanta");
                    i += "Atlas".len();
                    continue;
                }
            }
        }

        let ch = text[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }

    out
}

fn is_protected_before(byte: Option<u8>) -> bool {
    matches!(byte, Some(b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_' | b'-' | b'\\' | b'/' | b'.'))
}

fn is_protected_after(bytes: &[u8], next_idx: usize) -> bool {
    let Some(&b) = bytes.get(next_idx) else {
        return false;
    };
    if matches!(b, b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'_' | b'-' | b'\\' | b'/') {
        return true;
    }
    // Keep module/file names like "Atlas.Core" or "atlas.json",
    // but allow sentence-ending "Atlas." followed by whitespace/end.
    if b == b'.' {
        return bytes.get(next_idx + 1).is_some_and(u8::is_ascii_alphanumeric);
    }
    false
}

#[cfg(test)]
mod tests {
    use super::sanitize_brand;

    #[test]
    fn replaces_cosmetic_progress_tags_and_prose() {
        assert_eq!(
            sanitize_brand("[2026-09-06 20:32:19] [-] [INFO] [AtlasProgress] 8/29"),
            "[2026-09-06 20:32:19] [-] [INFO] [VantaProgress] 8/29"
        );
        assert_eq!(
            sanitize_brand("[Atlas] Running the install plan as TrustedInstaller."),
            "[Vanta] Running the install plan as TrustedInstaller."
        );
        assert_eq!(
            sanitize_brand("[Atlas] Copying Atlas's files to C:\\Windows\\VantaOS\\Staging"),
            "[Vanta] Copying Vanta's files to C:\\Windows\\VantaOS\\Staging"
        );
        assert_eq!(
            sanitize_brand("Installing AtlasOS Toolbox failed: access denied"),
            "Installing Vanta Toolbox failed: access denied"
        );
        assert_eq!(
            sanitize_brand("7-Zip is installed, so Atlas keeps it and skips NanaZip."),
            "7-Zip is installed, so Vanta keeps it and skips NanaZip."
        );
        assert_eq!(
            sanitize_brand("Atlas Manager offers to put them back from Home."),
            "Vanta Manager offers to put them back from Home."
        );
        assert_eq!(
            sanitize_brand("Before installing Atlas."),
            "Before installing Vanta."
        );
        assert_eq!(
            sanitize_brand("Installed AtlasOS successfully."),
            "Installed Vanta successfully."
        );
    }

    #[test]
    fn preserves_real_paths_registry_keys_modules_and_packages() {
        let cases = [
            r"C:\Windows\VantaModules\Logs\install\vanta-install.log",
            r"C:\Windows\VantaOS\Staging\1\Executables\atlas.json",
            r"C:\Users\Test\AppData\Local\Vanta\Logs\install.log",
            r"C:\Program Files\Atlas Setup Recovery\AtlasManager.exe",
            r"HKLM\SOFTWARE\Vanta\Toolbox",
            r"HKU\Atlas_DefaultUser\Software\Policies\Microsoft\Windows\Personalization",
            "module=Atlas.Core.psm1",
            "Install-Atlas.ps1:86 char:5",
            "Write-AtlasLog failed",
            "Z-Atlas-NoDefender-Package~31bf3856ad364e35~amd64~~1.0.0.0",
            "atlas-v0.6.x-dark.theme",
            "ATLAS_PREP:{\"schema\":1}",
        ];
        for line in cases {
            assert_eq!(sanitize_brand(line), line, "real identifier must not be rewritten: {line}");
        }
    }

    #[test]
    fn mixes_cosmetic_and_real_names_on_the_same_line() {
        assert_eq!(
            sanitize_brand(
                "[Atlas] Atlas 0.6.0 from 'C:\\Windows\\VantaOS\\Staging' using HKLM\\SOFTWARE\\Vanta\\State (Z-Atlas-NoDefender-Package)"
            ),
            "[Vanta] Vanta 0.6.0 from 'C:\\Windows\\VantaOS\\Staging' using HKLM\\SOFTWARE\\Vanta\\State (Z-Atlas-NoDefender-Package)"
        );
    }
}
