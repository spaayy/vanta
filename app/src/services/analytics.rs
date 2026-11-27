//! Vanta Manager não envia telemetria: `send` existe só para os chamadores não mudarem.

pub fn send(_enabled: bool, _name: &'static str, _path: &'static str) {}

#[cfg(test)]
mod tests {
    #[test]
    fn analytics_never_leaves_the_pc() {
        super::send(true, "pageview", "iso/files");
    }
}
