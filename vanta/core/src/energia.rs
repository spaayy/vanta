//! Energia do Vanta Tools: o plano Vanta (criado com GUID próprio) e as opções de CPU, só como comandos `powercfg` (puro: quem executa é o `vanta-sys`).
//!
//! Regras (auditoria do Hito): o plano Vanta é uma CÓPIA do plano que o usuário tinha ativo, então os tempos de tela e
//! de suspensão e todos os valores na bateria (DC) ficam como estão; só se escreve em AC. A suspensão seletiva de USB
//! não é tocada. `PROCTHROTTLEMIN 100`, núcleos sem estacionar e boost agressivo são opções SEPARADAS, nunca forçadas.

/// Equilibrado do Windows: o destino do Desfazer quando o plano anterior sumiu.
pub const PLANO_EQUILIBRADO: &str = "381b4222-f694-41f0-9685-ff5bb260df2e";

const SUB_PROCESSOR: &str = "54533251-82be-4824-96c1-47b60b740d00";
const SUB_DISK: &str = "0012ee47-9041-4b5d-9b77-535fba8b1442";
const NVME_NOPPME: &str = "fc7372b6-ab2d-43ee-8797-15e9841f2cca";
const THROTTLE_STATES: &str = "3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb";
const PERF_CHECK_INTERVAL: &str = "4d2b0152-7d5c-498b-88e2-34345392a2c5";
const PROCTHROTTLEMIN: &str = "893dee8e-2bef-41e0-89c6-b55d0929964c";
const CPMINCORES: &str = "0cc5b647-c1df-4637-891a-dec35c318583";
const PERFBOOSTMODE: &str = "be337238-0d82-4146-a960-4f3749d470c7";

/// O que o usuário pode ligar. Cada opção é independente; nada daqui entra num nível sozinho.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum OpcaoEnergia {
    /// O plano Vanta (cópia do plano ativo + 3 valores em AC). Pré-requisito das outras opções.
    PlanoVanta,
    /// `CPMINCORES 100` em AC: núcleos sem estacionar. Aquece mais.
    NucleosSemEstacionar,
    /// `PERFBOOSTMODE 2` em AC: boost agressivo. Aquece mais.
    BoostAgressivo,
    /// `PROCTHROTTLEMIN 100` em AC: CPU sempre no máximo. Só por escolha explícita, com aviso de calor e bateria.
    CpuMinima100,
}

impl OpcaoEnergia {
    pub const TODAS: [OpcaoEnergia; 4] =
        [Self::PlanoVanta, Self::NucleosSemEstacionar, Self::BoostAgressivo, Self::CpuMinima100];

    pub fn id(self) -> &'static str {
        match self {
            Self::PlanoVanta => "plano-vanta",
            Self::NucleosSemEstacionar => "nucleos-sem-estacionar",
            Self::BoostAgressivo => "boost-agressivo",
            Self::CpuMinima100 => "cpu-min-100",
        }
    }

    /// O aviso que a tela mostra ao lado da opção (vazio = sem aviso).
    pub fn aviso(self) -> &'static str {
        match self {
            Self::PlanoVanta => "",
            Self::NucleosSemEstacionar | Self::BoostAgressivo => "Mais calor e mais consumo; no notebook vale só na tomada.",
            Self::CpuMinima100 => "A CPU fica sempre no máximo: muito calor e consumo, e pode reduzir a vida útil da bateria. Só na tomada.",
        }
    }

    fn valores_ac(self) -> &'static [(&'static str, &'static str, &'static str)] {
        match self {
            Self::PlanoVanta => &[
                (SUB_DISK, NVME_NOPPME, "0"),
                (SUB_PROCESSOR, THROTTLE_STATES, "0"),
                (SUB_PROCESSOR, PERF_CHECK_INTERVAL, "200"),
            ],
            Self::NucleosSemEstacionar => &[(SUB_PROCESSOR, CPMINCORES, "100")],
            Self::BoostAgressivo => &[(SUB_PROCESSOR, PERFBOOSTMODE, "2")],
            Self::CpuMinima100 => &[(SUB_PROCESSOR, PROCTHROTTLEMIN, "100")],
        }
    }
}

/// Um GUID de plano no formato `8-4-4-4-12` hexadecimal (entra em linha de comando: nunca texto livre).
pub fn is_guid(text: &str) -> bool {
    let parts: Vec<&str> = text.split('-').collect();
    parts.len() == 5
        && [8, 4, 4, 4, 12].iter().zip(&parts).all(|(n, p)| p.len() == *n && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// O GUID do plano ativo, de uma linha como `Power Scheme GUID: 381b...  (Balanced)` (qualquer idioma).
pub fn parse_active_scheme(output: &str) -> Option<String> {
    let found: Vec<String> = output
        .split(|c: char| !(c.is_ascii_hexdigit() || c == '-'))
        .filter(|t| is_guid(t))
        .map(str::to_ascii_lowercase)
        .collect();
    (found.len() == 1).then(|| found[0].clone())
}

/// O plano de execução: argumentos de `powercfg.exe`, na ordem.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ComandosEnergia {
    pub comandos: Vec<Vec<String>>,
}

fn cmd(args: &[&str]) -> Vec<String> {
    args.iter().map(|a| (*a).to_owned()).collect()
}

/// Nome do plano criado pelo Vanta. A autoria é comprovada pelo GUID guardado no diário E por este nome na lista de planos.
pub const NOME_PLANO: &str = "Vanta Power Scheme";

/// O plano é do Vanta? Só se o diário guarda o GUID (criado por ele, o Windows escolhe um GUID novo) E a lista de planos
/// (`powercfg /list`) ainda mostra esse GUID com o nome do Vanta. Um plano de outro programa (por exemplo, o Atlas) ou do
/// usuário nunca passa nesta prova, mesmo com GUID parecido.
pub fn plano_e_nosso(guid_no_diario: Option<&str>, lista_de_planos: &str) -> Option<String> {
    let guid = guid_no_diario.map(str::to_ascii_lowercase).filter(|g| is_guid(g))?;
    let linha = lista_de_planos.lines().find(|l| l.to_ascii_lowercase().contains(&guid))?;
    linha.contains(&format!("({NOME_PLANO})")).then_some(guid)
}

/// Passo 1: cria o plano do Vanta como CÓPIA do plano que o usuário tinha ativo (tempos de tela e suspensão e valores da
/// bateria vêm junto). O Windows escolhe o GUID novo e o imprime; `parse_active_scheme` o lê. Nunca se usa GUID fixo.
pub fn criar(anterior: &str) -> Result<Vec<String>, String> {
    if !is_guid(anterior) {
        return Err(format!("GUID de plano inválido: {anterior}"));
    }
    Ok(cmd(&["/duplicatescheme", anterior]))
}

/// Passo 2: dá o nome, escreve os valores AC das opções e ativa o plano (`plano_vanta` = o GUID provado como do Vanta).
/// Erro: GUID inválido, ou nenhuma opção marcada.
pub fn configurar(plano_vanta: &str, opcoes: &[OpcaoEnergia]) -> Result<ComandosEnergia, String> {
    if !is_guid(plano_vanta) {
        return Err(format!("GUID de plano inválido: {plano_vanta}"));
    }
    if opcoes.is_empty() {
        return Err("Nenhuma opção de energia marcada.".to_owned());
    }
    let mut out = ComandosEnergia::default();
    out.comandos.push(cmd(&["/changename", plano_vanta, NOME_PLANO, "Vanta AC power policy; screen, sleep and battery values kept."]));
    for opcao in OpcaoEnergia::TODAS.iter().filter(|o| opcoes.contains(o)) {
        for (sub, setting, value) in opcao.valores_ac() {
            out.comandos.push(cmd(&["/setacvalueindex", plano_vanta, sub, setting, value]));
        }
    }
    out.comandos.push(cmd(&["/setactive", plano_vanta]));
    Ok(out)
}

/// Desfazer: reativa o plano anterior (ou o Equilibrado, se ele sumiu) e apaga SÓ o plano que o Vanta provou ser seu
/// (`plano_vanta_proprio` vem de [`plano_e_nosso`]). Sem prova, nada é apagado.
pub fn desfazer(anterior: Option<&str>, anterior_instalado: bool, plano_vanta_proprio: Option<&str>) -> ComandosEnergia {
    let proprio = plano_vanta_proprio.filter(|g| is_guid(g));
    let alvo = anterior.filter(|g| is_guid(g) && Some(*g) != proprio && anterior_instalado).unwrap_or(PLANO_EQUILIBRADO);
    let mut comandos = vec![cmd(&["/setactive", alvo])];
    if let Some(g) = proprio {
        comandos.push(cmd(&["/delete", g]));
    }
    ComandosEnergia { comandos }
}

/// Modo de energia "Melhor desempenho" do Windows 11 em AC.
pub const MODO_MELHOR_DESEMPENHO: &str = "ded574b5-45a0-4f42-8737-46345c09c238";

const DECLARA_API: &str = "Add-Type -Namespace V -Name P -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"powrprof.dll\")] public static extern uint PowerSetUserConfiguredACPowerMode(ref System.Guid g); [System.Runtime.InteropServices.DllImport(\"powrprof.dll\")] public static extern uint PowerGetUserConfiguredACPowerMode(out System.Guid g);'; ";

/// Lê o modo de energia AC atual (melhor esforço): imprime o GUID do modo ou `indisponivel`.
pub fn script_ler_modo_ac() -> String {
    format!("$ErrorActionPreference='Stop'; try {{ {DECLARA_API}$g=[guid]::Empty; if ([V.P]::PowerGetUserConfiguredACPowerMode([ref]$g) -eq 0) {{ $g.ToString() }} else {{ 'indisponivel' }} }} catch {{ 'indisponivel' }}")
}

/// Define o modo de energia AC (melhor esforço): imprime `ok` ou `indisponivel`. `modo` é validado (entra no script).
pub fn script_modo_ac(modo: &str) -> Result<String, String> {
    if !is_guid(modo) {
        return Err(format!("GUID de modo inválido: {modo}"));
    }
    Ok(format!("$ErrorActionPreference='Stop'; try {{ {DECLARA_API}$g=[guid]'{modo}'; if ([V.P]::PowerSetUserConfiguredACPowerMode([ref]$g) -eq 0) {{ 'ok' }} else {{ 'indisponivel' }} }} catch {{ 'indisponivel' }}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    const USER: &str = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c";
    const NOVO: &str = "5d1b9a3e-0a52-4c1e-9d37-2f6f1c0a7b11";
    const ATLAS: &str = "11111111-1111-1111-1111-111111111111";

    fn todos(c: &ComandosEnergia) -> String {
        c.comandos.iter().map(|c| c.join(" ")).collect::<Vec<_>>().join("\n")
    }

    #[test]
    fn the_plan_is_a_copy_created_with_a_windows_chosen_guid_never_a_fixed_one() {
        assert_eq!(criar(USER).unwrap(), vec!["/duplicatescheme", USER], "sem GUID de destino: o Windows escolhe");
        assert!(criar("8c5e; calc").is_err());
        let text = todos(&configurar(NOVO, &[OpcaoEnergia::PlanoVanta]).unwrap());
        assert!(!text.contains(ATLAS) && !text.contains("/duplicatescheme"));
        assert!(text.starts_with(&format!("/changename {NOVO} {NOME_PLANO}")) && text.ends_with(&format!("/setactive {NOVO}")));
    }

    #[test]
    fn the_vanta_plan_never_touches_screen_sleep_dc_or_usb() {
        let text = todos(&configurar(NOVO, &[OpcaoEnergia::PlanoVanta]).unwrap());
        assert!(!text.contains("/setdcvalueindex"), "valores da bateria ficam como estão");
        for proibido in ["7516b95f-f776-4464-8c53-06167f40cc99", "238c9fa8-0aad-41ed-83f4-97be242c8f20", "2a737441-1930-4402-8d77-b2bebba308a3", "4f971e89-eebd-4455-a8de-9e59040e7347"] {
            assert!(!text.contains(proibido), "tela, suspensão e USB não são tocados: {proibido}");
        }
        assert_eq!(text.matches("/setacvalueindex").count(), 3);
        // nada de CPU 100% sem pedir
        assert!(!text.contains("893dee8e") && !text.contains("0cc5b647") && !text.contains("be337238"));
    }

    #[test]
    fn cpu_options_are_separate_and_explicit() {
        assert!(configurar(NOVO, &[]).is_err());
        let text = todos(&configurar(NOVO, &[OpcaoEnergia::CpuMinima100]).unwrap());
        assert!(text.contains(&format!("/setacvalueindex {NOVO} 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100")));
        assert!(!text.contains("0cc5b647"));
        let todas = todos(&configurar(NOVO, &OpcaoEnergia::TODAS).unwrap());
        assert!(todas.contains("0cc5b647") && todas.contains("be337238") && todas.contains("893dee8e"));
        assert!(OpcaoEnergia::CpuMinima100.aviso().contains("calor") && OpcaoEnergia::PlanoVanta.aviso().is_empty());
    }

    #[test]
    fn only_a_plan_the_journal_and_the_list_prove_to_be_ours_is_deleted() {
        let lista = format!("Power Scheme GUID: {USER}  (Balanced)\nPower Scheme GUID: {NOVO}  ({NOME_PLANO}) *\nPower Scheme GUID: {ATLAS}  (Atlas Power Scheme)\n");
        assert_eq!(plano_e_nosso(Some(NOVO), &lista).as_deref(), Some(NOVO));
        assert_eq!(plano_e_nosso(Some(ATLAS), &lista), None, "o plano do Atlas, com GUID fixo conhecido, não é nosso");
        assert_eq!(plano_e_nosso(None, &lista), None, "sem registro no diário não há prova");
        assert_eq!(plano_e_nosso(Some(USER), &lista), None, "um plano do usuário com GUID diferente também não");
        assert_eq!(plano_e_nosso(Some("zzzz"), &lista), None);
        let c = desfazer(Some(USER), true, Some(NOVO));
        assert_eq!(c.comandos, vec![vec!["/setactive".to_owned(), USER.to_owned()], vec!["/delete".to_owned(), NOVO.to_owned()]]);
        // sem prova: volta ao plano anterior e NÃO apaga nada
        assert_eq!(desfazer(Some(USER), true, None).comandos, vec![vec!["/setactive".to_owned(), USER.to_owned()]]);
        // plano anterior sumiu, ausente ou é o próprio Vanta: Equilibrado
        for (g, ok) in [(Some(USER), false), (None, true), (Some(NOVO), true)] {
            assert_eq!(desfazer(g, ok, Some(NOVO)).comandos[0][1], PLANO_EQUILIBRADO);
        }
    }

    #[test]
    fn guids_are_validated_before_reaching_a_command_line_or_script() {
        assert!(configurar("8c5e; calc", &[OpcaoEnergia::PlanoVanta]).is_err());
        assert!(!is_guid("g8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c") && is_guid(USER));
        assert_eq!(parse_active_scheme("GUID do Esquema de Energia: 381b4222-F694-41f0-9685-ff5bb260df2e  (Equilibrado)").as_deref(), Some("381b4222-f694-41f0-9685-ff5bb260df2e"));
        assert_eq!(parse_active_scheme("sem guid"), None);
        assert!(script_modo_ac(MODO_MELHOR_DESEMPENHO).unwrap().contains("ded574b5"));
        assert!(script_modo_ac("x'; calc; '").is_err());
        assert!(script_ler_modo_ac().contains("PowerGetUserConfiguredACPowerMode"));
    }
}
