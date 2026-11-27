//! Página Avançado: dispositivos do `disable-pnp`. Fora de TODOS os níveis; só opt-in individual, validado pelo
//! `InstanceId` do inventário, com Desfazer (`Enable-PnpDevice`). Nunca `-Force`, nunca LLDP/protocolo de rede global.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dispositivo {
    pub instance_id: String,
    pub nome: String,
    pub classe: String,
    pub ativo: bool,
}

/// Classes que nunca se desligam por aqui (entrada, disco, vídeo, rede, bateria, processador, sistema, USB, Bluetooth).
pub const CLASSES_PROTEGIDAS: [&str; 17] = [
    "Keyboard", "Mouse", "HIDClass", "DiskDrive", "SCSIAdapter", "HDC", "Display", "Net", "Battery", "Processor", "System", "Volume", "USB", "Bluetooth",
    // o TPM 2.0 (BitLocker, PIN do Windows Hello, Valorant/Vanguard), o próprio computador e as filas de impressão
    "SecurityDevices", "Computer", "PrintQueue",
];

/// `InstanceId` (prefixo) que nunca se desliga, qualquer que seja a classe: todo o barramento virtual do Hyper-V (VMBUS).
pub const PREFIXOS_PROTEGIDOS: [&str; 1] = ["VMBUS\\"];

/// O dispositivo nunca pode ser desligado pelo Vanta: classe protegida (inclui TODA a classe `System`), `InstanceId` do
/// VMBUS, TPM pelo nome, ou dispositivo SEM nome amigável (não dá para a pessoa saber o que está desligando).
pub fn protegido(d: &Dispositivo) -> bool {
    motivo_protegido(d).is_some()
}

/// Por que o dispositivo é protegido (`None` = pode ser oferecido como elegível).
pub fn motivo_protegido(d: &Dispositivo) -> Option<Recusa> {
    let id = d.instance_id.to_ascii_uppercase();
    let nome = d.nome.to_ascii_lowercase();
    if nome.trim().is_empty() {
        return Some(Recusa::DispositivoProtegido("sem nome amigável".to_owned()));
    }
    if PREFIXOS_PROTEGIDOS.iter().any(|p| id.starts_with(p)) {
        return Some(Recusa::DispositivoProtegido("barramento virtual do Hyper-V (VMBUS)".to_owned()));
    }
    if id.split(['\\', '&']).any(|seg| seg == "PNP0501") {
        return Some(Recusa::DispositivoProtegido("porta serial 16550 (PNP0501)".to_owned()));
    }
    if nome.contains("trusted platform module") {
        return Some(Recusa::DispositivoProtegido("TPM (BitLocker, Windows Hello, Valorant)".to_owned()));
    }
    CLASSES_PROTEGIDAS.iter().any(|c| c.eq_ignore_ascii_case(&d.classe)).then(|| Recusa::ClasseProtegida(d.classe.clone()))
}

/// `InstanceId` como o Windows escreve (`PCI\VEN_8086&DEV_1234\3&11583659&0&FE`): letras, dígitos e `\ & _ - . { } @ #`.
pub fn is_instance_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 200
        && id.contains('\\')
        && id.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '\\' | '&' | '_' | '-' | '.' | '{' | '}' | '@' | '#'))
}

/// Lê o inventário de [`SCRIPT_INVENTARIO`]: `InstanceId<TAB>Nome<TAB>Classe<TAB>Status` por linha.
pub fn parse_inventario(text: &str) -> Vec<Dispositivo> {
    text.lines()
        .filter_map(|l| {
            let p: Vec<&str> = l.trim_end_matches('\r').split('\t').collect();
            (p.len() == 4 && is_instance_id(p[0]))
                .then(|| Dispositivo { instance_id: p[0].to_owned(), nome: p[1].to_owned(), classe: p[2].to_owned(), ativo: p[3] == "OK" })
        })
        .collect()
}

/// O script que lista o inventário (somente leitura).
pub const SCRIPT_INVENTARIO: &str =
    "Get-PnpDevice -PresentOnly | ForEach-Object { $_.InstanceId + \"`t\" + ($_.FriendlyName -replace \"`t\",' ') + \"`t\" + $_.Class + \"`t\" + $_.Status }";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Recusa {
    InstanceIdInvalido,
    NaoEstaNoInventario,
    ClasseProtegida(String),
    /// Protegido por motivo próprio (VMBUS, TPM, sem nome amigável).
    DispositivoProtegido(String),
}

impl std::fmt::Display for Recusa {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Recusa::InstanceIdInvalido => f.write_str("InstanceId inválido."),
            Recusa::NaoEstaNoInventario => f.write_str("O dispositivo não está no inventário deste PC; atualize a lista."),
            Recusa::ClasseProtegida(c) => write!(f, "Dispositivos da classe {c} não podem ser desligados pelo Vanta."),
            Recusa::DispositivoProtegido(why) => write!(f, "Este dispositivo não pode ser desligado pelo Vanta: {why}."),
        }
    }
}

/// Valida o pedido contra o inventário lido agora e devolve o script de desligar (`Disable-PnpDevice`, sem `-Force`).
pub fn desligar(instance_id: &str, inventario: &[Dispositivo]) -> Result<String, Recusa> {
    if !is_instance_id(instance_id) {
        return Err(Recusa::InstanceIdInvalido);
    }
    let d = inventario.iter().find(|d| d.instance_id == instance_id).ok_or(Recusa::NaoEstaNoInventario)?;
    if let Some(motivo) = motivo_protegido(d) {
        return Err(motivo);
    }
    Ok(format!("Disable-PnpDevice -InstanceId '{instance_id}' -Confirm:$false -ErrorAction Stop"))
}

/// O Desfazer. Só exige id válido (o dispositivo desligado continua no inventário).
pub fn religar(instance_id: &str) -> Result<String, Recusa> {
    if !is_instance_id(instance_id) {
        return Err(Recusa::InstanceIdInvalido);
    }
    Ok(format!("Enable-PnpDevice -InstanceId '{instance_id}' -Confirm:$false -ErrorAction Stop"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const INV: &str = "PCI\\VEN_8086&DEV_1C3A\\3&11583659&0&FB\tIntel(R) Management Engine Interface\tSystem\tOK\r\nHID\\X\\1\tMouse\tMouse\tOK\r\nPCI\\VEN_8086&DEV_1C10\\3&1\tPCI Express Root Port\tSystem\tOK\r\nlixo sem tabs\r\nPCI\\VEN_10DE&DEV_1\\4&2\tNVIDIA GPU\tDisplay\tOK\r\nROOT\\MEDIA\\0000\tSpeaker legado\tMEDIA\tOK\r\n";

    #[test]
    fn the_inventory_is_parsed_and_junk_lines_are_dropped() {
        let inv = parse_inventario(INV);
        assert_eq!(inv.len(), 5);
        assert!(inv[0].ativo && inv[0].classe == "System");
    }

    #[test]
    fn only_inventory_devices_of_unprotected_classes_can_be_disabled() {
        let inv = parse_inventario(INV);
        assert_eq!(
            desligar("ROOT\\MEDIA\\0000", &inv).unwrap(),
            "Disable-PnpDevice -InstanceId 'ROOT\\MEDIA\\0000' -Confirm:$false -ErrorAction Stop"
        );
        assert_eq!(desligar("PCI\\VEN_10DE&DEV_1\\4&2", &inv), Err(Recusa::ClasseProtegida("Display".into())));
        assert_eq!(desligar("PCI\\VEN_8086&DEV_1C3A\\3&11583659&0&FB", &inv), Err(Recusa::ClasseProtegida("System".into())), "Intel ME fica protegido");
        assert_eq!(desligar("PCI\\VEN_8086&DEV_1C10\\3&1", &inv), Err(Recusa::ClasseProtegida("System".into())), "outros System ficam protegidos");
        assert_eq!(desligar("ROOT\\OUTRO\\0", &inv), Err(Recusa::NaoEstaNoInventario));
        assert_eq!(desligar("X'; calc; '\\1", &inv), Err(Recusa::InstanceIdInvalido));
    }

    #[test]
    fn only_the_common_device_of_a_mixed_list_is_eligible() {
        let mk = |id: &str, nome: &str, classe: &str| Dispositivo { instance_id: id.into(), nome: nome.into(), classe: classe.into(), ativo: true };
        let inv = vec![
            mk("ACPI\\MSFT0101\\1", "Trusted Platform Module 2.0", "SecurityDevices"),
            mk("ACPI_HAL\\PNP0C08\\0", "Computador com ACPI x64", "Computer"),
            mk("ROOT\\PRINTQUEUE\\0000", "Fila de Impress\u{e3}o da Raiz", "PrintQueue"),
            mk("VMBUS\\POWERDEVICE\\1", "Microsoft Hyper-V Power Device", "System"),
            mk("VMBUS\\{abc}\\2", "Qualquer coisa do barramento", "MEDIA"),
            mk("ACPI\\MSFT0101\\2", "Trusted Platform Module 2.0", "Outro"),
            mk("ACPI\\PNP0103\\0", "High precision event timer", "System"),
            mk("ACPI\\PNP0501\\1", "Communications Port (COM1)", "System"),
            mk("ROOT\\SEMNOME\\0", "  ", "MEDIA"),
            mk("ROOT\\MEDIA\\0000", "Speaker legado", "MEDIA"),
        ];
        let elegiveis: Vec<&str> = inv.iter().filter(|d| !protegido(d)).map(|d| d.nome.as_str()).collect();
        assert_eq!(elegiveis, ["Speaker legado"], "só o dispositivo comum sai elegível");
        for d in &inv[..9] {
            assert!(desligar(&d.instance_id, &inv).is_err(), "{}", d.nome);
        }
        assert!(desligar(&inv[9].instance_id, &inv).is_ok());
        // a regra é de lógica, não de botão: o motivo vem junto para a tela mostrar
        assert!(matches!(motivo_protegido(&inv[3]), Some(Recusa::DispositivoProtegido(m)) if m.contains("VMBUS")));
        assert!(matches!(motivo_protegido(&inv[8]), Some(Recusa::DispositivoProtegido(m)) if m.contains("sem nome")));
        assert!(matches!(motivo_protegido(&inv[6]), Some(Recusa::ClasseProtegida(c)) if c == "System"), "nenhum System");
        assert!(matches!(motivo_protegido(&inv[7]), Some(Recusa::DispositivoProtegido(m)) if m.contains("PNP0501")), "porta serial PNP0501");
    }

    #[test]
    fn serial_pnp0501_is_protected_regardless_of_class_or_language() {
        let comum = Dispositivo { instance_id: "ROOT\\MEDIA\\0000".into(), nome: "Speaker legado".into(), classe: "MEDIA".into(), ativo: true };
        for id in ["ACPI\\PNP0501\\1", "acpi\\pnp0501\\1"] {
            for classe in ["System", "Ports", "Outro"] {
                for nome in ["Communications Port (COM1)", "Porta de comunica\u{e7}\u{e3}o (COM1)"] {
                    let d = Dispositivo { instance_id: id.into(), nome: nome.into(), classe: classe.into(), ativo: true };
                    assert!(protegido(&d), "{id} {classe} {nome}");
                    assert!(matches!(motivo_protegido(&d), Some(Recusa::DispositivoProtegido(_))), "{id} {classe} {nome}");
                    let inv = vec![d.clone(), comum.clone()];
                    assert!(matches!(desligar(&d.instance_id, &inv), Err(Recusa::DispositivoProtegido(_))), "{id} {classe} {nome}");
                    assert!(desligar(&comum.instance_id, &inv).is_ok());
                }
            }
        }
        let outra_porta = Dispositivo { instance_id: "ACPI\\PNP05010\\1".into(), nome: "Outra porta".into(), classe: "Ports".into(), ativo: true };
        assert!(!protegido(&outra_porta), "segmento diferente de PNP0501 nao deve ser bloqueado por engano");
    }

    #[test]
    fn rollback_exists_and_force_or_lldp_are_never_used() {
        assert!(religar("ROOT\\MEDIA\\0000").unwrap().starts_with("Enable-PnpDevice"));
        assert_eq!(religar("a b"), Err(Recusa::InstanceIdInvalido));
        let text = desligar("ROOT\\MEDIA\\0000", &parse_inventario(INV)).unwrap();
        assert!(!text.to_lowercase().contains("force") && !text.to_lowercase().contains("lldp"));
        assert!(SCRIPT_INVENTARIO.starts_with("Get-PnpDevice") && !SCRIPT_INVENTARIO.contains("Disable"));
    }
}
