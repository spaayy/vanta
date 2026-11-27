//! Níveis de otimização do Vanta Tools (Leve, Equilibrado, Competitivo): atalhos sobre o catálogo manual.
//!
//! Um nível não tem itens próprios: ele marca ajustes do `tweaks.json` (campo `nivel`, cumulativo). O estado vem do
//! registro real (`TweakEngine::read`), então o plano separa o que FALTA ("ligar") do que "Já foi feito pelo Vanta".
//! Qualquer ajuste público também se liga solto ([`plano_manual`]); quem mexe na marcação de um nível fica "Personalizado".

use std::collections::HashSet;

use crate::tweaks::{ApplyResult, SystemStore, Tweak, TweakEngine, TweakError, TweakState};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Nivel {
    Leve,
    Equilibrado,
    Competitivo,
}

impl Nivel {
    pub const TODOS: [Nivel; 3] = [Nivel::Leve, Nivel::Equilibrado, Nivel::Competitivo];

    /// O valor do campo `nivel` do `tweaks.json`.
    pub fn id(self) -> &'static str {
        match self {
            Nivel::Leve => "leve",
            Nivel::Equilibrado => "equilibrado",
            Nivel::Competitivo => "competitivo",
        }
    }

    pub fn from_id(id: &str) -> Option<Nivel> {
        Self::TODOS.into_iter().find(|n| n.id() == id)
    }
}

/// O que se detectou no PC antes de aplicar.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Deteccao {
    /// O disco do sistema é SSD.
    pub ssd: bool,
    pub nvidia: bool,
    pub bateria: bool,
    /// Domínio, Entra ou MDM: só o Leve fica liberado.
    pub gerenciado: bool,
}

/// Script (somente leitura) que o `vanta-sys` roda para detectar o PC; imprime `chave=valor`, uma por linha.
pub const SCRIPT_DETECCAO: &str = r#"$ErrorActionPreference='SilentlyContinue'
$sd = $env:SystemDrive.Substring(0,1)
$disk = Get-Partition -DriveLetter $sd | Get-Disk | Get-PhysicalDisk | Select-Object -First 1
'ssd=' + [int]($disk.MediaType -eq 'SSD')
'bateria=' + [int]($null -ne (Get-CimInstance Win32_Battery | Select-Object -First 1))
$dom = [int](Get-CimInstance Win32_ComputerSystem).PartOfDomain
$aad = [int]((& dsregcmd.exe /status 2>$null) -match 'AzureAdJoined\s*:\s*YES').Count
$mdm = 0
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' | ForEach-Object { $p = Get-ItemProperty $_.PSPath; if ($p.EnrollmentState -eq 1 -and ($p.ProviderID -eq 'MS DM Server' -or $p.DiscoveryServiceFullURL)) { $mdm = 1 } }
'gerenciado=' + [int]($dom -or $aad -or $mdm)
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
'pro=' + [int]($cv.EditionID -match 'Professional|Enterprise|Education|Workstation|ServerRdsh')
'build=' + [int]$cv.CurrentBuildNumber"#;

/// Lê a saída de [`SCRIPT_DETECCAO`]. O que faltar vira o valor CONSERVADOR: sem SSD (nada de `sysmain-off`), PC gerenciado
/// (só o Leve) e Windows sem edição/build conhecidos (ajustes condicionados ficam de fora).
pub fn ler_deteccao(saida: &str) -> (Deteccao, Ambiente) {
    let get = |chave: &str| saida.lines().find_map(|l| l.trim().strip_prefix(chave)?.strip_prefix('=').map(|v| v.trim().to_owned()));
    let flag = |chave: &str| get(chave).map(|v| v == "1");
    (
        Deteccao { ssd: flag("ssd").unwrap_or(false), nvidia: false, bateria: flag("bateria").unwrap_or(false), gerenciado: flag("gerenciado").unwrap_or(true) },
        Ambiente { pro: flag("pro").unwrap_or(false), build: get("build").and_then(|b| b.parse().ok()).unwrap_or(0) },
    )
}

/// Edição e versão do Windows, lidas à parte de [`Deteccao`]. Desconhecido (o padrão) é conservador: os ajustes que
/// pedem `pro` ou `build26100` ficam de fora até a tela informar o ambiente real (`plano_manual_em`/`plano_nivel_em`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Ambiente {
    /// Windows Pro, Enterprise ou Education (políticas de grupo valem).
    pub pro: bool,
    /// Número da build (`26100` = 24H2).
    pub build: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PlanoNivel {
    /// Ajustes que faltam neste PC (o que será ligado).
    pub ligar: Vec<String>,
    /// "Já feito pelo Vanta": o registro real já está no valor do ajuste.
    pub ja_feito: Vec<String>,
    /// Ajustes fora do plano, com o motivo (ex.: `sysmain-off`: só em SSD).
    pub pulados: Vec<(String, String)>,
    pub avisos: Vec<String>,
    pub reiniciar: bool,
}

impl PlanoNivel {
    /// Tudo do nível já está aplicado: o botão fica desligado ("Já aplicado").
    pub fn ja_aplicado(&self) -> bool {
        self.ligar.is_empty() && !self.ja_feito.is_empty()
    }

    /// Os ids que o nível marca (faltando ou já feitos).
    pub fn selecao(&self) -> HashSet<&str> {
        self.ligar.iter().chain(&self.ja_feito).map(String::as_str).collect()
    }
}

fn rank(level: &str) -> Option<usize> {
    Nivel::from_id(level).map(|n| Nivel::TODOS.iter().position(|t| *t == n).unwrap_or(0))
}

/// Os ajustes que o nível inclui (cumulativo: o Competitivo inclui o Equilibrado e o Leve). Só públicos, nunca fixos.
pub fn ajustes_do_nivel(nivel: Nivel, tweaks: &[Tweak]) -> Vec<&Tweak> {
    let max = rank(nivel.id()).unwrap_or(0);
    tweaks.iter().filter(|t| t.public && !t.locked && t.level.as_deref().and_then(rank).is_some_and(|r| r <= max)).collect()
}

/// Separa uma lista de ajustes (de um nível ou escolhida à mão) entre faltando e já feito, lendo o registro real.
pub fn plano_manual<S: SystemStore>(ids: &[&str], tweaks: &[Tweak], det: &Deteccao, store: &mut S) -> PlanoNivel {
    plano_manual_em(ids, tweaks, det, &Ambiente::default(), store)
}

/// Este ajuste pode ser LIGADO neste PC? `Err(motivo)` = não (nada deve ser gravado); `Ok(Some(aviso))` = pode, com aviso.
/// O campo `requer` do `tweaks.json` aceita várias condições separadas por vírgula, todas obrigatórias:
/// `ssd`, `pro` (Windows Pro ou superior), `build26100` (24H2 ou mais novo), `nao_gerenciado` e `nvidia` (só aviso).
/// Condição desconhecida recusa (falha fechada). Desligar/desfazer um ajuste nunca passa por aqui.
pub fn elegibilidade(tweak: &Tweak, det: &Deteccao, amb: &Ambiente) -> Result<Option<String>, String> {
    let mut aviso = None;
    for condicao in tweak.requires.as_deref().unwrap_or("").split(',').map(str::trim).filter(|c| !c.is_empty()) {
        match condicao {
            "ssd" if !det.ssd => return Err("só vale em SSD".to_owned()),
            "pro" if !amb.pro => return Err("vale só no Windows Pro ou superior".to_owned()),
            "build26100" if amb.build < 26100 => return Err("vale só no Windows 11 24H2 (build 26100) ou mais novo".to_owned()),
            "nao_gerenciado" if det.gerenciado => return Err("PC da empresa: o administrador decide".to_owned()),
            "nvidia" if !det.nvidia => aviso = Some(format!("{}: pensado para placa NVIDIA; sem ela o efeito pode ser nenhum.", tweak.id)),
            "ssd" | "pro" | "build26100" | "nao_gerenciado" | "nvidia" => {}
            outra => return Err(format!("condição desconhecida ({outra})")),
        }
    }
    Ok(aviso)
}

/// A ÚNICA porta de gravação manual de um ajuste: confere a elegibilidade para ligar E para desligar e só então grava. Num PC
/// inelegível nada é escrito nem apagado (desligar também escreve valores ou apaga políticas que o Vanta não provou ter
/// aplicado). A reversão de algo que o Vanta aplicou continua em `diario::desfazer`, que usa o diário `niveis.json` e não
/// passa por aqui. Use esta função na aba Ajustes (clique individual e lote) e onde mais um ajuste for gravado fora de um plano.
pub fn aplicar_ajuste<S: SystemStore>(store: &mut S, tweak: &Tweak, enable: bool, det: &Deteccao, amb: &Ambiente) -> Result<ApplyResult, crate::tweaks::TweakError> {
    elegibilidade(tweak, det, amb).map_err(crate::tweaks::TweakError::NotEligible)?;
    TweakEngine::new(store).apply(tweak, enable)
}

/// Igual a [`plano_manual`], conhecendo a edição e a build do Windows.
pub fn plano_manual_em<S: SystemStore>(ids: &[&str], tweaks: &[Tweak], det: &Deteccao, amb: &Ambiente, store: &mut S) -> PlanoNivel {
    let mut plano = PlanoNivel::default();
    for id in ids {
        let Some(tweak) = tweaks.iter().find(|t| t.id == *id && t.public && !t.locked) else {
            plano.pulados.push(((*id).to_owned(), "ajuste desconhecido, fixo ou fora da edição".to_owned()));
            continue;
        };
        match elegibilidade(tweak, det, amb) {
            Err(motivo) => {
                plano.pulados.push((tweak.id.clone(), motivo));
                continue;
            }
            Ok(Some(aviso)) => plano.avisos.push(aviso),
            Ok(None) => {}
        }
        if !tweak.services.is_empty() && tweak.registry.is_empty() && tweak.services.iter().all(|s| store.service_lookup(&s.name) == crate::tweaks::ServiceLookup::Missing) {
            plano.pulados.push((tweak.id.clone(), "os serviços não existem neste Windows".to_owned()));
            continue;
        }
        match TweakEngine::new(store).read(tweak) {
            TweakState::On => plano.ja_feito.push(tweak.id.clone()),
            _ => {
                plano.reiniciar |= tweak.restart;
                plano.ligar.push(tweak.id.clone());
            }
        }
    }
    plano
}

/// O plano de um nível neste PC. PC gerenciado: só o Leve (aviso "PC da empresa"). Puro: só lê o registro.
pub fn plano_nivel<S: SystemStore>(nivel: Nivel, tweaks: &[Tweak], det: &Deteccao, store: &mut S) -> PlanoNivel {
    plano_nivel_em(nivel, tweaks, det, &Ambiente::default(), store)
}

/// Igual a [`plano_nivel`], conhecendo a edição e a build do Windows.
pub fn plano_nivel_em<S: SystemStore>(nivel: Nivel, tweaks: &[Tweak], det: &Deteccao, amb: &Ambiente, store: &mut S) -> PlanoNivel {
    let efetivo = if det.gerenciado { Nivel::Leve } else { nivel };
    let ids: Vec<&str> = ajustes_do_nivel(efetivo, tweaks).iter().map(|t| t.id.as_str()).collect();
    let mut plano = plano_manual_em(&ids, tweaks, det, amb, store);
    if det.gerenciado && nivel != Nivel::Leve {
        plano.avisos.insert(0, "PC da empresa: só o nível Leve fica liberado.".to_owned());
    }
    plano
}

/// Liga o que falta; um ajuste que falha não para os outros. Idempotente: rodar de novo não acha nada a ligar.
pub fn aplicar_plano<S: SystemStore>(plano: &PlanoNivel, tweaks: &[Tweak], store: &mut S) -> Vec<(String, Result<ApplyResult, TweakError>)> {
    plano
        .ligar
        .iter()
        .filter_map(|id| tweaks.iter().find(|t| t.id == *id))
        .map(|t| (t.id.clone(), TweakEngine::new(store).apply(t, true)))
        .collect()
}

/// "Personalizado": a marcação atual difere da que o nível marcaria.
pub fn personalizado(marcados: &HashSet<&str>, plano: &PlanoNivel) -> bool {
    *marcados != plano.selecao()
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::*;
    use crate::tweaks::{RegValue, parse_catalog};

    #[derive(Default)]
    struct Fake(HashMap<String, RegValue>, HashMap<String, String>);

    impl SystemStore for Fake {
        fn get_value(&self, key: &str, name: &str) -> Option<RegValue> {
            self.0.get(&format!("{key}|{name}")).cloned()
        }
        fn set_value(&mut self, key: &str, name: &str, _kind: &str, value: RegValue) {
            self.0.insert(format!("{key}|{name}"), value);
        }
        fn delete_value(&mut self, key: &str, name: &str) {
            self.0.remove(&format!("{key}|{name}"));
        }
        fn get_service_start(&self, service: &str) -> Option<String> {
            self.1.get(service).cloned()
        }
        fn set_service_start(&mut self, service: &str, start: &str) {
            self.1.insert(service.to_owned(), start.to_owned());
        }
    }

    fn catalog() -> Vec<Tweak> {
        parse_catalog(include_str!("../catalog/tweaks.json")).unwrap()
    }

    const TUDO: Deteccao = Deteccao { ssd: true, nvidia: true, bateria: false, gerenciado: false };
    const AMB: Ambiente = Ambiente { pro: true, build: 26100 };

    /// Um PC de fábrica: os serviços de cada ajuste existem, no início `desligado` (o do Windows).
    fn pc(tweaks: &[Tweak]) -> Fake {
        let mut f = Fake::default();
        for s in tweaks.iter().flat_map(|t| &t.services) {
            f.1.insert(s.name.clone(), s.off.clone());
        }
        f
    }

    #[test]
    fn the_levels_are_cumulative_with_the_agreed_counts() {
        let t = catalog();
        let n = |l| ajustes_do_nivel(l, &t).len();
        assert_eq!((n(Nivel::Leve), n(Nivel::Equilibrado), n(Nivel::Competitivo)), (24, 30, 44));
    }

    #[test]
    fn no_level_touches_security_nor_personal_tweaks() {
        let t = catalog();
        for tweak in t.iter().filter(|t| t.level.is_some()) {
            assert!(tweak.public && !tweak.locked, "{} é pessoal ou fixo", tweak.id);
        }
        for id in ["vbs-hvci", "smartscreen", "uac-secure", "motw", "crash-dump", "notifications-off", "dark-theme"] {
            assert!(t.iter().find(|x| x.id == id).is_some_and(|x| x.level.is_none()), "{id} não pode ter nível");
        }
        // o campo só aceita os três níveis
        assert!(t.iter().filter_map(|x| x.level.as_deref()).all(|l| Nivel::from_id(l).is_some()));
    }

    #[test]
    fn the_plan_reads_the_real_registry_and_is_idempotent() {
        let t = catalog();
        let mut store = pc(&t);
        let plano = plano_nivel_em(Nivel::Leve, &t, &TUDO, &AMB, &mut store);
        assert_eq!((plano.ligar.len(), plano.ja_feito.len()), (24, 0));
        assert!(plano.reiniciar == t.iter().filter(|x| plano.ligar.contains(&x.id)).any(|x| x.restart));
        assert!(aplicar_plano(&plano, &t, &mut store).iter().all(|(_, r)| r.is_ok()));
        let depois = plano_nivel_em(Nivel::Leve, &t, &TUDO, &AMB, &mut store);
        assert_eq!((depois.ligar.len(), depois.ja_feito.len()), (0, 24));
        assert!(depois.ja_aplicado());
        // um valor desfeito (por atualização do Windows) volta a faltar
        let primeiro = t.iter().find(|x| x.id == plano.ligar[0]).unwrap();
        TweakEngine::new(&mut store).apply(primeiro, false).unwrap();
        assert_eq!(plano_nivel_em(Nivel::Leve, &t, &TUDO, &AMB, &mut store).ligar, vec![primeiro.id.clone()]);
    }

    #[test]
    fn a_higher_level_only_adds_what_the_lower_one_already_did() {
        let t = catalog();
        let mut store = pc(&t);
        let leve = plano_nivel_em(Nivel::Leve, &t, &TUDO, &AMB, &mut store);
        aplicar_plano(&leve, &t, &mut store);
        let comp = plano_nivel_em(Nivel::Competitivo, &t, &TUDO, &AMB, &mut store);
        assert_eq!((comp.ja_feito.len(), comp.ligar.len()), (24, 20));
    }

    #[test]
    fn detection_skips_or_warns_and_a_managed_pc_only_gets_leve() {
        let t = catalog();
        let mut store = pc(&t);
        let sem_ssd = plano_nivel_em(Nivel::Equilibrado, &t, &Deteccao { ssd: false, nvidia: true, ..TUDO }, &AMB, &mut store);
        assert!(sem_ssd.pulados.iter().any(|(id, _)| id == "sysmain-off") && !sem_ssd.ligar.contains(&"sysmain-off".to_owned()));
        let sem_nvidia = plano_nivel_em(Nivel::Competitivo, &t, &Deteccao { nvidia: false, ..TUDO }, &AMB, &mut store);
        assert!(sem_nvidia.avisos.iter().any(|a| a.starts_with("mpo-off")) && sem_nvidia.ligar.contains(&"mpo-off".to_owned()));
        let empresa = plano_nivel_em(Nivel::Competitivo, &t, &Deteccao { gerenciado: true, ..TUDO }, &AMB, &mut store);
        assert_eq!(empresa.ligar.len(), 24);
        assert!(empresa.avisos[0].starts_with("PC da empresa"));
    }

    #[test]
    fn the_detection_report_is_read_and_missing_values_are_conservative() {
        let (d, a) = ler_deteccao("ssd=1
bateria=1
gerenciado=0
pro=1
build=26300
");
        assert_eq!((d.ssd, d.bateria, d.gerenciado, a.pro, a.build), (true, true, false, true, 26300));
        let (d, a) = ler_deteccao("");
        assert_eq!((d.ssd, d.gerenciado, a.pro, a.build), (false, true, false, 0), "sem leitura: sem SSD, gerenciado, build 0");
        let (d, _) = ler_deteccao("ssd=0
gerenciado=1
lixo");
        assert!(!d.ssd && d.gerenciado);
        assert!(SCRIPT_DETECCAO.contains("Win32_Battery") && SCRIPT_DETECCAO.contains("dsregcmd") && SCRIPT_DETECCAO.contains("Enrollments"));
    }

    #[test]
    fn eligibility_is_checked_in_one_place_before_any_write() {
        let t = catalog();
        let get = |id: &str| t.iter().find(|x| x.id == id).unwrap().clone();
        let click = get("clicktodo-off");
        let home_novo = Ambiente { pro: false, build: 26300 };
        let pro_velho = Ambiente { pro: true, build: 22631 };
        assert!(elegibilidade(&click, &TUDO, &home_novo).unwrap_err().contains("Pro"), "build nova sozinha não basta");
        assert!(elegibilidade(&click, &TUDO, &pro_velho).unwrap_err().contains("24H2"));
        assert!(elegibilidade(&click, &TUDO, &AMB).is_ok());
        // a porta de gravação recusa sem escrever nada, ao ligar e ao desligar; o Desfazer do diário é outro caminho
        let mut store = pc(&t);
        let r = aplicar_ajuste(&mut store, &click, true, &TUDO, &home_novo);
        assert!(matches!(r, Err(crate::tweaks::TweakError::NotEligible(_))));
        assert!(store.0.is_empty(), "nada foi gravado");
        aplicar_ajuste(&mut store, &click, true, &TUDO, &AMB).unwrap();
        assert!(!store.0.is_empty());
        let antes = store.0.clone();
        assert!(matches!(aplicar_ajuste(&mut store, &click, false, &TUDO, &home_novo), Err(crate::tweaks::TweakError::NotEligible(_))), "desligar à mão em PC inelegível também é recusado");
        assert_eq!(store.0, antes, "nada foi apagado nem escrito");
        // o que o Vanta aplicou (e anotou no diário) volta pelo Desfazer, que não depende da elegibilidade
        let mut diario = crate::diario::Diario::default();
        let mut s2 = pc(&t);
        let ids = vec![click.id.clone()];
        crate::diario::aplicar_em(&mut s2, &t, &ids, None, &TUDO, &AMB, &mut diario, &mut |_| Ok(()));
        assert!(!s2.0.is_empty());
        crate::diario::desfazer(&mut s2, &mut diario, &click.id).unwrap();
        assert!(s2.0.is_empty(), "o Desfazer do diário devolve o valor anterior (nenhum) mesmo no Home");
        aplicar_ajuste(&mut store, &click, false, &TUDO, &AMB).unwrap();
        // várias condições; uma desconhecida falha fechada; nvidia é só aviso
        let mut x = get("copilot-off");
        x.requires = Some("pro, build26100".into());
        assert!(elegibilidade(&x, &TUDO, &home_novo).is_err() && elegibilidade(&x, &TUDO, &AMB).is_ok());
        x.requires = Some("pro,algo-novo".into());
        assert!(elegibilidade(&x, &TUDO, &AMB).unwrap_err().contains("desconhecida"));
        x.requires = Some("nvidia".into());
        assert!(elegibilidade(&x, &Deteccao { nvidia: false, ..TUDO }, &AMB).unwrap().is_some());
    }

    #[test]
    fn linguistic_data_policy_lives_in_the_documented_textinput_key() {
        let t = catalog();
        let typing = t.iter().find(|x| x.id == "typing-data-off").unwrap();
        let policy = typing.registry.iter().find(|e| e.name == "AllowLinguisticDataCollection").expect("a política existe");
        assert_eq!(policy.key, r"HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput");
        assert_eq!((policy.on.as_i64(), policy.off.is_null()), (Some(0), true));
        assert!(!typing.registry.iter().any(|e| e.key.contains(r"Windows\TextInput")), "o caminho antigo, errado, não volta");
    }

    #[test]
    fn conditional_tweaks_wait_for_the_edition_the_build_and_unmanaged_pcs() {
        let t = catalog();
        let mut store = pc(&t);
        let sem_ambiente = plano_nivel(Nivel::Leve, &t, &TUDO, &mut store);
        for id in ["lockscreen-tips-off", "clicktodo-off"] {
            assert!(sem_ambiente.pulados.iter().any(|(p, _)| p == id), "{id} só com o ambiente conhecido");
        }
        let home = plano_manual_em(&["lockscreen-tips-off", "clicktodo-off"], &t, &TUDO, &Ambiente { pro: false, build: 22631 }, &mut store);
        assert_eq!((home.ligar.len(), home.pulados.len()), (0, 2));
        let ok = plano_manual_em(&["lockscreen-tips-off", "clicktodo-off"], &t, &TUDO, &AMB, &mut store);
        assert_eq!(ok.ligar.len(), 2);
        // os que o Hito mandou pular não existem no catálogo
        for id in ["store-search-off", "standby-net-off", "disable-pnp", "ai-service-manual"] {
            assert!(!t.iter().any(|x| x.id == id), "{id} fica fora");
        }
        // e nenhum item de dispositivo entra em nível
        assert!(!t.iter().any(|x| x.level.is_some() && x.id.contains("pnp")));
    }

    #[test]
    fn manual_freedom_works_on_any_public_tweak_and_marks_a_level_as_custom() {
        let t = catalog();
        let mut store = pc(&t);
        // Leve + "CPU/energia" do Competitivo: qualquer ajuste público entra solto
        let manual = plano_manual_em(&["copilot-off", "transparency-off", "taskbar-left", "nao-existe", "vbs-hvci"], &t, &TUDO, &AMB, &mut store);
        assert_eq!(manual.ligar.len(), 3);
        assert!(manual.pulados.iter().any(|(id, _)| id == "vbs-hvci"), "segurança não entra solta");
        assert!(manual.pulados.iter().any(|(id, _)| id == "nao-existe"));
        let leve = plano_nivel_em(Nivel::Leve, &t, &TUDO, &AMB, &mut store);
        assert!(!personalizado(&leve.selecao(), &leve));
        let mut marcados = leve.selecao();
        marcados.insert("transparency-off");
        assert!(personalizado(&marcados, &leve));
        marcados.remove("transparency-off");
        marcados.remove("copilot-off");
        assert!(personalizado(&marcados, &leve));
    }

    #[test]
    fn equilibrado_with_missing_fax_closes_as_applied_and_notes_fax() {
        let t = catalog();
        let mut store = pc(&t);
        store.1.remove("Fax"); // simula Windows 26H2 sem o serviço Fax
        let antes = plano_nivel_em(Nivel::Equilibrado, &t, &TUDO, &AMB, &mut store);
        assert!(antes.ligar.iter().any(|id| id == "services-manual"));
        let mut diario = crate::diario::Diario::default();
        let results = crate::diario::aplicar_em(&mut store, &t, &antes.ligar, Some("equilibrado"), &TUDO, &AMB, &mut diario, &mut |_| Ok(()));
        assert!(results.iter().all(|(_, r)| r.is_ok()));
        let (_, res) = results.iter().find(|(id, _)| id == "services-manual").expect("services-manual aplicado");
        let applied = res.as_ref().unwrap();
        assert_eq!(applied.missing_services, vec!["Fax"]);
        let note = applied.note.as_deref().expect("nota cita o Fax ausente");
        assert!(note.contains("Fax") && note.contains("ausente"), "nota inesperada: {note}");
        let depois = plano_nivel_em(Nivel::Equilibrado, &t, &TUDO, &AMB, &mut store);
        assert!(depois.ligar.is_empty(), "não sobra nada para aplicar: {:?}", depois.ligar);
        assert!(depois.ja_aplicado(), "nível fecha como Já aplicado mesmo sem Fax");
    }
}
