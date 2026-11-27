//! Telas da v1.1 do Vanta Tools: Otimizar (Leve, Equilibrado, Competitivo + Personalizado +
//! "Já feito pelo Vanta" + Diário/Desfazer + Visual Vanta) e as páginas manuais ligadas ao
//! backend real (`vanta_core::{niveis, diario, energia, servicos, apps, avancado}` e `vanta_sys::niveis`).

use std::collections::{HashMap, HashSet};

use gpui::{
    AnyElement, Context, FontWeight, IntoElement, ObjectFit, ParentElement, Role, SharedString,
    Styled, StyledImage, Toggled, div, img, prelude::*, px,
};
use vanta_core::apps::{self, EstadoApp, NOTA_REINSTALAR, PROTEGIDOS, ROTULO_REINSTALAR};
use vanta_core::avancado::{self, Dispositivo};
use vanta_core::diario::{self, Status};
use vanta_core::energia::OpcaoEnergia;
use vanta_core::niveis::{
    Ambiente, Deteccao, Nivel, PlanoNivel, ajustes_do_nivel, personalizado, plano_manual_em,
    plano_nivel_em,
};
use vanta_core::servicos::{self, EstadoServico, SERVICOS, StartType};
use vanta_core::tweaks::{ServiceLookup, SystemStore, TweakState};
use vanta_sys::niveis::{
    ProcessExecutor, app_reinstalar, app_remover, caminho_diario, dispositivo_desligar,
    dispositivo_religar, dispositivos, energia_desfazer, energia_ligar, estado_app, gravar_diario,
};
use vanta_sys::store::RegistryStore;

use super::app::{Msg, NoticeKind, Page, ToolsApp};
use super::data::GpuVendor;
use super::kit::{self, Kind, a, c};
use super::theme::*;
use crate::theme::{FONT_MONO, FONT_TEXT};
use crate::ui::focus_ring;

/// Ajustes reais do `tweaks.json` exibidos nas páginas manuais da v1.1.
pub(super) const POWER_IDS: &[&str] = &["hibernate-off", "power-throttle-off"];
pub(super) const APPS_IDS: &[&str] = &[
    "copilot-off",
    "recall-off",
    "widgets-off",
    "store-autoupdate-off",
    "bg-apps-off",
];
pub(super) const SERVICES_IDS: &[&str] = &[
    "services-manual",
    "diagtrack-off",
    "sysmain-off",
    "search-index-off",
    "delivery-opt-off",
];

fn level_index(nivel: Nivel) -> usize {
    match nivel {
        Nivel::Leve => 0,
        Nivel::Equilibrado => 1,
        Nivel::Competitivo => 2,
    }
}

fn level_meta(nivel: Nivel) -> (&'static str, &'static str, &'static str) {
    match nivel {
        Nivel::Leve => (
            "Leve",
            "Limpo e rápido, seguro para trabalho",
            "Privacidade, IA intrusiva, anúncios, dicas, mouse e menus. Não desliga serviços nem recursos de escritório.",
        ),
        Nivel::Equilibrado => (
            "Equilibrado",
            "Leve + desempenho sem perder conforto",
            "Soma hibernação, serviços opcionais em Manual, Game DVR, MMCSS para jogos, HAGS e SysMain (em SSD).",
        ),
        Nivel::Competitivo => (
            "Competitivo",
            "Máximo foco em jogos e resposta",
            "Soma prioridade Win32, MPO (NVIDIA), timer global, otimização de janela e ajustes extras para menor latência.",
        ),
    }
}

fn level_glyph(nivel: Nivel) -> &'static str {
    match nivel {
        Nivel::Leve => "\u{E734}",
        Nivel::Equilibrado => "\u{E9D9}",
        Nivel::Competitivo => "\u{E945}",
    }
}

fn power_option_copy(op: OpcaoEnergia) -> (&'static str, &'static str) {
    match op {
        OpcaoEnergia::PlanoVanta => (
            "Plano de energia Vanta",
            "Copia seu plano ativo atual e ajusta apenas parâmetros de resposta na tomada, preservando tela, suspensão, bateria e USB.",
        ),
        OpcaoEnergia::NucleosSemEstacionar => (
            "Núcleos sem estacionar (CPMINCORES 100)",
            "Mantém todos os núcleos do processador prontos na tomada para evitar microtravamentos.",
        ),
        OpcaoEnergia::BoostAgressivo => (
            "Boost agressivo do processador (PERFBOOSTMODE 2)",
            "Prioriza clock máximo sob carga quando conectado à energia.",
        ),
        OpcaoEnergia::CpuMinima100 => (
            "CPU mínima em 100% (PROCTHROTTLEMIN 100)",
            "Trava o estado mínimo do processador em 100% na tomada. Escolha opcional e separada.",
        ),
    }
}

fn start_type_label(st: StartType) -> &'static str {
    match st {
        StartType::Auto => "Automático",
        StartType::Manual => "Manual",
        StartType::Disabled => "Desativado",
    }
}

impl ToolsApp {
    /// Combina a detecção real (`vanta_sys::niveis::detectar`) com a detecção de GPU NVIDIA do diagnóstico.
    pub(super) fn deteccao_e_ambiente(&self) -> (Deteccao, Ambiente) {
        let (mut det, amb) = self.env_detected.unwrap_or((
            Deteccao { ssd: false, nvidia: false, bateria: false, gerenciado: false },
            Ambiente::default(),
        ));
        if let Some(pc) = &self.pc {
            det.nvidia = pc.gpu.iter().any(|gpu| gpu.vendor == GpuVendor::Nvidia);
        }
        (det, amb)
    }

    /// Recalcula os planos dos 3 níveis e o estado dos serviços gerenciáveis lendo o registro real.
    pub(super) fn refresh_level_plans(&mut self) {
        let (det, amb) = self.deteccao_e_ambiente();
        let mut store = RegistryStore::new();
        self.level_plans = [
            plano_nivel_em(Nivel::Leve, &self.tweaks, &det, &amb, &mut store),
            plano_nivel_em(Nivel::Equilibrado, &self.tweaks, &det, &amb, &mut store),
            plano_nivel_em(Nivel::Competitivo, &self.tweaks, &det, &amb, &mut store),
        ];
        self.refresh_service_states(&store);
    }

    pub(super) fn refresh_service_states(&mut self, store: &RegistryStore) {
        let mut states = HashMap::with_capacity(SERVICOS.len());
        let mut currents = HashMap::with_capacity(SERVICOS.len());
        for svc in &SERVICOS {
            states.insert(svc.nome, servicos::estado_checado(store, svc.nome, StartType::Manual));
            let cur = match store.service_lookup(svc.nome) {
                ServiceLookup::Found(start) => StartType::from_nome(&start),
                ServiceLookup::Missing | ServiceLookup::Denied(_) => None,
            };
            currents.insert(svc.nome, cur);
        }
        self.service_states = states;
        self.service_current = currents;
    }

    pub(super) fn plan_of(&self, nivel: Nivel) -> &PlanoNivel {
        &self.level_plans[level_index(nivel)]
    }

    pub(super) fn effective_level_selection(&self, nivel: Nivel) -> HashSet<String> {
        if nivel == self.selected_level
            && let Some(custom) = &self.level_custom
        {
            return custom.clone();
        }
        self.plan_of(nivel).selecao().into_iter().map(str::to_owned).collect()
    }

    pub(super) fn is_selected_level_custom(&self) -> bool {
        let Some(custom) = &self.level_custom else {
            return false;
        };
        let refs: HashSet<&str> = custom.iter().map(String::as_str).collect();
        personalizado(&refs, self.plan_of(self.selected_level))
    }

    pub(super) fn select_level(&mut self, nivel: Nivel, cx: &mut Context<Self>) {
        self.selected_level = nivel;
        self.level_custom = None;
        self.optimize_outcome = None;
        self.optimize_notice = None;
        self.optimize_info_notes.clear();
        self.optimize_errors.clear();
        self.prefs.selected_level = nivel.id().to_owned();
        self.prefs.custom_tweaks = None;
        self.prefs.save();
        cx.notify();
    }

    fn toggle_level_item(&mut self, tweak_id: String, cx: &mut Context<Self>) {
        let plano = self.plan_of(self.selected_level).clone();
        let mut selection = self.effective_level_selection(self.selected_level);
        if !selection.remove(&tweak_id) {
            selection.insert(tweak_id);
        }
        let refs: HashSet<&str> = selection.iter().map(String::as_str).collect();
        if personalizado(&refs, &plano) {
            let mut sorted: Vec<String> = selection.iter().cloned().collect();
            sorted.sort();
            self.level_custom = Some(selection);
            self.prefs.custom_tweaks = Some(sorted);
        } else {
            self.level_custom = None;
            self.prefs.custom_tweaks = None;
        }
        self.prefs.selected_level = self.selected_level.id().to_owned();
        self.prefs.save();
        self.optimize_outcome = None;
        self.optimize_notice = None;
        self.optimize_info_notes.clear();
        self.optimize_errors.clear();
        cx.notify();
    }

    fn reset_level_customization(&mut self, cx: &mut Context<Self>) {
        self.level_custom = None;
        self.prefs.custom_tweaks = None;
        self.prefs.save();
        self.optimize_outcome = None;
        self.optimize_notice = None;
        self.optimize_info_notes.clear();
        self.optimize_errors.clear();
        cx.notify();
    }

    /// Aplica os ajustes marcados gravando o estado anterior no diário (`niveis.json`) para Desfazer.
    fn apply_selected_level(&mut self, cx: &mut Context<Self>) {
        let (det, amb) = self.deteccao_e_ambiente();
        let selection = self.effective_level_selection(self.selected_level);
        let mut ordered_ids: Vec<&str> = self
            .tweaks
            .iter()
            .filter(|t| selection.contains(&t.id))
            .map(|t| t.id.as_str())
            .collect();
        if ordered_ids.is_empty() {
            return;
        }
        ordered_ids.dedup();
        let mut store = RegistryStore::new();
        let plano = plano_manual_em(&ordered_ids, &self.tweaks, &det, &amb, &mut store);
        if plano.ligar.is_empty() {
            self.optimize_outcome = Some((0, false));
            self.optimize_info_notes.clear();
            self.optimize_errors.clear();
            self.refresh_states();
            cx.notify();
            return;
        }
        let path = caminho_diario();
        let nivel_id = self.selected_level.id();
        let mut gravar = |d: &diario::Diario| gravar_diario(&path, d);
        let results = diario::aplicar_em(
            &mut store,
            &self.tweaks,
            &plano.ligar,
            Some(nivel_id),
            &det,
            &amb,
            &mut self.diario,
            &mut gravar,
        );
        let store_errors = store.take_errors();
        let mut ok_count = 0usize;
        let mut errors: Vec<(String, String)> = Vec::new();
        let mut info_notes: Vec<String> = Vec::new();
        for (id, res) in results {
            let title = self
                .copy
                .get(&id)
                .filter(|c| !c.title.is_empty())
                .map(|c| c.title.clone())
                .or_else(|| self.tweaks.iter().find(|t| t.id == id).map(|t| t.title.clone()))
                .unwrap_or(id);
            match res {
                Ok(applied) => {
                    ok_count += 1;
                    if let Some(note) = applied.note
                        && !info_notes.contains(&note)
                    {
                        info_notes.push(note);
                    }
                }
                Err(err) => errors.push((title, err)),
            }
        }
        if !store_errors.is_empty() {
            errors.push((
                "Permissão de administrador".to_owned(),
                format!(
                    "O Windows negou {} gravação(ões) no registro ({}).",
                    store_errors.len(),
                    store_errors[0]
                ),
            ));
        }
        self.optimize_errors = errors;
        self.optimize_notice = None;
        self.optimize_info_notes = info_notes;
        self.optimize_outcome = Some((ok_count, plano.reiniciar));
        self.refresh_states();
        cx.notify();
    }

    fn journal_tweak_ids(&self) -> Vec<String> {
        self.diario
            .entradas
            .iter()
            .filter(|e| {
                e.status == Status::Concluido
                    && e.id != "energia"
                    && !e.id.starts_with("app:")
                    && !e.id.starts_with("pnp:")
            })
            .map(|e| e.id.clone())
            .collect()
    }

    fn undo_journal_ids(&mut self, ids: Vec<String>, cx: &mut Context<Self>) {
        if ids.is_empty() {
            return;
        }
        let mut store = RegistryStore::new();
        let mut undone = 0usize;
        let mut errors: Vec<(String, String)> = Vec::new();
        for id in ids {
            if id == "energia" {
                self.start_power_undo(cx);
                continue;
            }
            if let Some(chave) = id.strip_prefix("app:") {
                self.start_app_action(chave.to_owned(), false, cx);
                continue;
            }
            if let Some(instance_id) = id.strip_prefix("pnp:") {
                self.start_device_action(instance_id.to_owned(), false, cx);
                continue;
            }
            match diario::desfazer(&mut store, &mut self.diario, &id) {
                Ok(()) => undone += 1,
                Err(err) => errors.push((id, err)),
            }
        }
        let store_errors = store.take_errors();
        if !store_errors.is_empty() {
            errors.push(("Permissão de administrador".to_owned(), store_errors[0].clone()));
        }
        if let Err(err) = gravar_diario(&caminho_diario(), &self.diario) {
            errors.push(("Diário".to_owned(), err));
        }
        self.optimize_errors = errors;
        self.optimize_info_notes.clear();
        if undone > 0 {
            self.optimize_outcome = None;
            self.optimize_notice = Some(format!(
                "{undone} ajuste(s) revertido(s) para o valor anterior registrado no diário."
            ));
        }
        self.refresh_states();
        cx.notify();
    }

    // ---------- Ações assíncronas das páginas manuais ----------

    pub(super) fn load_apps_in_background(&mut self) {
        if self.apps_loading {
            return;
        }
        self.apps_loading = true;
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let exec = ProcessExecutor;
            let mut map = HashMap::with_capacity(apps::APPS.len());
            for app in &apps::APPS {
                let st = estado_app(&exec, app.chave).unwrap_or(EstadoApp::Desconhecido);
                map.insert(app.chave.to_owned(), st);
            }
            let _ = tx.send(Msg::AppsLoaded(map));
        });
    }

    pub(super) fn load_devices_in_background(&mut self) {
        if self.devices_loading {
            return;
        }
        self.devices_loading = true;
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let result = dispositivos(&ProcessExecutor);
            let _ = tx.send(Msg::DevicesLoaded(result));
        });
    }

    fn toggle_power_option(&mut self, op: OpcaoEnergia, cx: &mut Context<Self>) {
        if self.power_busy {
            return;
        }
        if !self.power_selected.remove(&op) {
            self.power_selected.insert(op);
            if op != OpcaoEnergia::PlanoVanta {
                self.power_selected.insert(OpcaoEnergia::PlanoVanta);
            }
        } else if op == OpcaoEnergia::PlanoVanta {
            self.power_selected.clear();
        }
        self.power_feedback = None;
        cx.notify();
    }

    fn start_power_apply(&mut self, cx: &mut Context<Self>) {
        if self.power_busy || self.power_selected.is_empty() {
            return;
        }
        let opcoes: Vec<OpcaoEnergia> = OpcaoEnergia::TODAS
            .into_iter()
            .filter(|op| self.power_selected.contains(op))
            .collect();
        self.power_busy = true;
        self.power_feedback = None;
        self.power_warnings.clear();
        let tx = self.tx.clone();
        let mut diario_copy = self.diario.clone();
        std::thread::spawn(move || {
            let path = caminho_diario();
            let mut gravar = |d: &diario::Diario| gravar_diario(&path, d);
            let result = energia_ligar(&ProcessExecutor, &opcoes, &mut diario_copy, &mut gravar);
            let _ = tx.send(Msg::PowerDone { result, diario: diario_copy, was_undo: false });
        });
        cx.notify();
    }

    fn start_power_undo(&mut self, cx: &mut Context<Self>) {
        if self.power_busy {
            return;
        }
        self.power_busy = true;
        self.power_feedback = None;
        self.power_warnings.clear();
        let tx = self.tx.clone();
        let mut diario_copy = self.diario.clone();
        std::thread::spawn(move || {
            let path = caminho_diario();
            let result = energia_desfazer(&ProcessExecutor, &mut diario_copy)
                .and_then(|()| gravar_diario(&path, &diario_copy))
                .map(|()| Vec::new());
            let _ = tx.send(Msg::PowerDone { result, diario: diario_copy, was_undo: true });
        });
        cx.notify();
    }

    fn set_service_start(&mut self, nome: &'static str, alvo: StartType, cx: &mut Context<Self>) {
        let mut store = RegistryStore::new();
        let res = servicos::definir(&mut store, nome, alvo);
        let errs = store.take_errors();
        self.service_feedback = Some(match (res, errs.is_empty()) {
            (Ok(antes), true) => Ok(format!(
                "{nome}: alterado de {} para {}.",
                start_type_label(antes),
                start_type_label(alvo)
            )),
            (Ok(_), false) => Err(format!(
                "{nome}: o Windows negou o acesso ao registro ({}).",
                errs[0]
            )),
            (Err(err), _) => Err(err),
        });
        self.refresh_states();
        cx.notify();
    }

    fn reset_service_default(&mut self, nome: &'static str, cx: &mut Context<Self>) {
        let mut store = RegistryStore::new();
        let res = servicos::voltar_ao_padrao(&mut store, nome);
        let errs = store.take_errors();
        self.service_feedback = Some(match (res, errs.is_empty()) {
            (Ok(_), true) => Ok(format!("{nome}: restaurado para o padrão do Windows.")),
            (Ok(_), false) => Err(format!(
                "{nome}: o Windows negou o acesso ao registro ({}).",
                errs[0]
            )),
            (Err(err), _) => Err(err),
        });
        self.refresh_states();
        cx.notify();
    }

    fn start_app_action(&mut self, chave: String, is_remove: bool, cx: &mut Context<Self>) {
        if self.app_busy.is_some() {
            return;
        }
        self.app_busy = Some(chave.clone());
        self.app_feedback = None;
        let tx = self.tx.clone();
        let mut diario_copy = self.diario.clone();
        std::thread::spawn(move || {
            let exec = ProcessExecutor;
            let path = caminho_diario();
            let result = if is_remove {
                let mut gravar = |d: &diario::Diario| gravar_diario(&path, d);
                app_remover(&exec, &chave, &mut diario_copy, &mut gravar)
            } else {
                app_reinstalar(&exec, &chave, &mut diario_copy)
                    .and_then(|()| gravar_diario(&path, &diario_copy))
            };
            let new_state = estado_app(&exec, &chave).unwrap_or(EstadoApp::Desconhecido);
            let _ = tx.send(Msg::AppActionDone {
                chave,
                is_remove,
                result,
                diario: diario_copy,
                new_state,
            });
        });
        cx.notify();
    }

    fn start_device_action(&mut self, instance_id: String, is_disable: bool, cx: &mut Context<Self>) {
        if self.device_busy.is_some() {
            return;
        }
        self.device_busy = Some(instance_id.clone());
        self.device_feedback = None;
        let tx = self.tx.clone();
        let mut diario_copy = self.diario.clone();
        std::thread::spawn(move || {
            let exec = ProcessExecutor;
            let path = caminho_diario();
            let result = if is_disable {
                let mut gravar = |d: &diario::Diario| gravar_diario(&path, d);
                dispositivo_desligar(&exec, &instance_id, &mut diario_copy, &mut gravar)
            } else {
                dispositivo_religar(&exec, &instance_id, &mut diario_copy)
                    .and_then(|()| gravar_diario(&path, &diario_copy))
            };
            let _ = tx.send(Msg::DeviceActionDone {
                instance_id,
                is_disable,
                result,
                diario: diario_copy,
            });
        });
        cx.notify();
    }

    pub(super) fn manual_counts(&self, page: Page) -> (usize, usize) {
        let indices = self.manual_tweak_indices(page);
        let on = indices.iter().filter(|&&i| self.states.get(i) == Some(&TweakState::On)).count();
        (on, indices.len())
    }

    pub(super) fn manual_tweak_indices(&self, page: Page) -> Vec<usize> {
        match page {
            Page::Power => self
                .tweaks
                .iter()
                .enumerate()
                .filter(|(_, t)| POWER_IDS.contains(&t.id.as_str()))
                .map(|(i, _)| i)
                .collect(),
            Page::Apps => self
                .tweaks
                .iter()
                .enumerate()
                .filter(|(_, t)| APPS_IDS.contains(&t.id.as_str()))
                .map(|(i, _)| i)
                .collect(),
            Page::Services => self
                .tweaks
                .iter()
                .enumerate()
                .filter(|(_, t)| SERVICES_IDS.contains(&t.id.as_str()))
                .map(|(i, _)| i)
                .collect(),
            Page::Advanced => self
                .tweaks
                .iter()
                .enumerate()
                .filter(|(_, t)| t.category == "Avancado")
                .map(|(i, _)| i)
                .collect(),
            _ => Vec::new(),
        }
    }

    // ---------- Página Otimizar (v1.1) ----------

    pub(super) fn optimize(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let selected = self.selected_level;
        let is_custom = self.is_selected_level_custom();
        let active_selection = self.effective_level_selection(selected);
        let active_plan = self.plan_of(selected).clone();
        let (det, amb) = self.deteccao_e_ambiente();
        let pendentes: Vec<String> = self.diario.pendentes().into_iter().map(str::to_owned).collect();
        let undo_ids = self.journal_tweak_ids();

        // Plano efetivo considerando a seleção atual (padrão do nível ou personalizada) e pulados do plano.
        let skipped_ids: HashSet<&str> = active_plan.pulados.iter().map(|(id, _)| id.as_str()).collect();
        let effective_to_apply: Vec<String> = self
            .tweaks
            .iter()
            .enumerate()
            .filter(|(i, t)| {
                active_selection.contains(&t.id)
                    && self.states.get(*i) != Some(&TweakState::On)
                    && !skipped_ids.contains(t.id.as_str())
            })
            .map(|(_, t)| t.id.clone())
            .collect();
        let effective_ja_feito: Vec<String> = self
            .tweaks
            .iter()
            .enumerate()
            .filter(|(i, t)| active_selection.contains(&t.id) && self.states.get(*i) == Some(&TweakState::On))
            .map(|(_, t)| t.id.clone())
            .collect();
        let effective_restart = self
            .tweaks
            .iter()
            .any(|t| effective_to_apply.contains(&t.id) && t.restart);
        let all_done = effective_to_apply.is_empty() && !effective_ja_feito.is_empty();

        // 3 cartões de nível (Leve, Equilibrado, Competitivo)
        let level_cards: Vec<AnyElement> = Nivel::TODOS
            .into_iter()
            .map(|nivel| {
                let (name, tagline, desc) = level_meta(nivel);
                let plan = self.plan_of(nivel).clone();
                let total = ajustes_do_nivel(nivel, &self.tweaks).len();
                let done_count = plan.ja_feito.len();
                let missing_count = plan.ligar.len();
                let is_active = nivel == selected;
                let show_custom = is_active && is_custom;
                let (badge_text, badge_bg, badge_fg): (String, u32, u32) = if show_custom {
                    ("Personalizado".to_owned(), 0x7C4EE02B, ACCENT_TEXT)
                } else if det.gerenciado && nivel != Nivel::Leve {
                    ("Bloqueado (empresa)".to_owned(), 0xFBBF2424, WARN)
                } else if plan.ja_aplicado() {
                    ("Já aplicado".to_owned(), 0x4ADE8024, OK)
                } else {
                    (format!("{missing_count} faltando"), 0x221E2CFF, INK_MUTED)
                };
                let focus = self.focus.get(&format!("opt-level-{}", nivel.id()), cx);
                div()
                    .id(("opt-level", level_index(nivel)))
                    .role(Role::RadioButton)
                    .aria_label(format!("Nível {name}: {tagline}"))
                    .aria_selected(is_active)
                    .track_focus(&focus.tab_index(0).tab_stop(true))
                    .flex_1()
                    .min_w(px(260.))
                    .p(px(20.))
                    .rounded(px(12.))
                    .border_1()
                    .border_color(if is_active { c(ACCENT_HOVER) } else { c(HAIRLINE) })
                    .bg(if is_active { a(0x1B1726EB) } else { a(SURFACE1) })
                    .cursor_pointer()
                    .hover(|s| {
                        s.border_color(if is_active { c(ACCENT_HOVER) } else { c(HAIRLINE_STRONG) })
                            .bg(a(0x1D1928F2))
                    })
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .flex()
                    .flex_col()
                    .gap(px(10.))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .justify_between()
                            .gap(px(8.))
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(8.))
                                    .text_color(if is_active { c(ACCENT_TEXT) } else { c(INK) })
                                    .child(kit::glyph(level_glyph(nivel), 16.))
                                    .child(kit::section_title(name)),
                            )
                            .child(
                                div()
                                    .px(px(9.))
                                    .py(px(3.))
                                    .rounded(px(999.))
                                    .bg(a(badge_bg))
                                    .font_family(FONT_TEXT)
                                    .font_weight(FontWeight::MEDIUM)
                                    .text_size(px(11.5))
                                    .text_color(c(badge_fg))
                                    .child(badge_text),
                            ),
                    )
                    .child(
                        div()
                            .font_family(FONT_TEXT)
                            .font_weight(FontWeight::MEDIUM)
                            .text_size(px(13.5))
                            .text_color(c(INK))
                            .child(tagline),
                    )
                    .child(kit::body(desc).text_color(c(INK_MUTED)))
                    .child(div().flex_1())
                    .child(
                        div()
                            .pt(px(6.))
                            .flex()
                            .flex_col()
                            .gap(px(6.))
                            .child(kit::meter(done_count as f32 / total.max(1) as f32, None))
                            .child(kit::caption(format!(
                                "{done_count} de {total} já ativos neste PC"
                            ))),
                    )
                    .on_click(cx.listener(move |this, _, _, cx| this.select_level(nivel, cx)))
                    .into_any_element()
            })
            .collect();

        // Hardware banner (estado Loading / Success da detecção real)
        let hw_status = if self.env_detected.is_none() || self.pc.is_none() {
            div()
                .w_full()
                .min_w_0()
                .flex()
                .items_start()
                .gap(px(8.))
                .text_color(c(INK_MUTED))
                .child(div().pt(px(2.)).child(kit::glyph("\u{E895}", 13.)))
                .child(
                    kit::caption(
                        "Detectando disco (SSD), bateria, PC gerenciado, edição/build do Windows e GPU…",
                    )
                    .flex_1()
                    .min_w_0(),
                )
        } else {
            let ssd_label = if det.ssd { "SSD no sistema" } else { "Sem SSD detectado" };
            let gpu_label = if det.nvidia { "GPU NVIDIA" } else { "Sem GPU NVIDIA" };
            let form_label = if det.bateria { "Notebook (bateria)" } else { "Desktop (tomada)" };
            let win_label = format!(
                "Windows {} · build {}",
                if amb.pro { "Pro" } else { "Home/outra" },
                amb.build
            );
            div()
                .flex()
                .flex_wrap()
                .items_center()
                .gap(px(12.))
                .child(kit::badge("\u{EDA2}", ssd_label))
                .child(kit::badge("\u{E7F4}", gpu_label))
                .child(kit::badge("\u{E83F}", form_label))
                .child(kit::badge("\u{E946}", win_label))
                .when(det.gerenciado, |d| {
                    d.child(
                        div()
                            .px(px(8.))
                            .py(px(2.))
                            .rounded(px(999.))
                            .bg(a(0xFBBF2424))
                            .child(kit::caption("PC da empresa (só Leve)").text_color(c(WARN))),
                    )
                })
        };

        // Avisos, erros de diário, pendentes interrompidos e feedback de execução
        let mut notices: Vec<AnyElement> = Vec::new();
        if let Some(err) = &self.diario_error {
            notices.push(Self::alert_box(
                ERR,
                "\u{EA39}",
                format!("Não foi possível ler o diário ({}): {err}. Nenhum arquivo foi apagado.", caminho_diario().display()),
                None,
            ));
        }
        if !pendentes.is_empty() {
            let ids_for_undo = pendentes.clone();
            let list = pendentes.join(", ");
            notices.push(Self::alert_box(
                WARN,
                "\u{E7BA}",
                format!("Operação interrompida encontrada no diário (em andamento): {list}."),
                Some(
                    kit::button("opt-undo-pending", "Desfazer pendentes", Kind::Secondary, Some("\u{E777}"), false)
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.undo_journal_ids(ids_for_undo.clone(), cx);
                        }))
                        .into_any_element(),
                ),
            ));
        }
        if !self.elevated {
            notices.push(Self::alert_box(
                WARN,
                "\u{E7BA}",
                "Abra o Vanta Tools como administrador para gravar níveis e manter o diário em ProgramData.".to_owned(),
                None,
            ));
        }
        for aviso in &active_plan.avisos {
            notices.push(Self::alert_box(WARN, "\u{E7BA}", aviso.clone(), None));
        }
        if !self.optimize_errors.is_empty() {
            let err_rows: Vec<AnyElement> = self
                .optimize_errors
                .iter()
                .map(|(title, msg)| {
                    kit::caption(format!("• {title}: {msg}"))
                        .w_full()
                        .min_w_0()
                        .text_color(c(ERR))
                        .into_any_element()
                })
                .collect();
            notices.push(
                div()
                    .w_full()
                    .min_w_0()
                    .px(px(16.))
                    .py(px(14.))
                    .rounded(px(10.))
                    .border_1()
                    .border_color(a(0xF8717166))
                    .bg(a(0x211319F0))
                    .flex()
                    .flex_wrap()
                    .items_start()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .min_w(px(240.))
                            .flex()
                            .flex_col()
                            .gap(px(4.))
                            .child(
                                div()
                                    .w_full()
                                    .min_w_0()
                                    .flex()
                                    .items_start()
                                    .gap(px(8.))
                                    .text_color(c(ERR))
                                    .child(div().pt(px(3.)).child(kit::glyph("\u{EA39}", 14.)))
                                    .child(
                                        kit::row_title("Alguns ajustes não puderam ser aplicados")
                                            .flex_1()
                                            .min_w_0()
                                            .text_color(c(ERR)),
                                    ),
                            )
                            .children(err_rows),
                    )
                    .child(
                        kit::button("opt-retry", "Tentar de novo", Kind::Secondary, Some("\u{E72C}"), false)
                            .on_click(cx.listener(|this, _, _, cx| this.apply_selected_level(cx))),
                    )
                    .into_any_element(),
            );
        } else if let Some((ok_count, needs_restart)) = self.optimize_outcome {
            let msg = if ok_count == 0 {
                "Tudo que estava marcado já se encontrava ativo neste PC.".to_owned()
            } else if needs_restart {
                format!(
                    "{ok_count} ajuste(s) aplicados e registrados no diário. Reinicie o PC para que todos entrem em vigor."
                )
            } else {
                format!("{ok_count} ajuste(s) aplicados e registrados no diário.")
            };
            notices.push(Self::alert_box(OK, "\u{E73E}", msg, None));
        } else if let Some(msg) = &self.optimize_notice {
            notices.push(Self::alert_box(OK, "\u{E73E}", msg.clone(), None));
        }
        for note in &self.optimize_info_notes {
            notices.push(Self::alert_box(ACCENT_TEXT, "\u{E946}", note.clone(), None));
        }

        // Lista editável de ajustes pendentes do nível escolhido
        let level_tweaks = ajustes_do_nivel(selected, &self.tweaks);
        let mut pending_rows: Vec<AnyElement> = Vec::new();
        for (idx, tweak) in level_tweaks.iter().enumerate() {
            if skipped_ids.contains(tweak.id.as_str()) {
                continue;
            }
            let is_already_on = self
                .tweaks
                .iter()
                .position(|t| t.id == tweak.id)
                .and_then(|pos| self.states.get(pos))
                == Some(&TweakState::On);
            if is_already_on {
                continue;
            }
            let checked = active_selection.contains(&tweak.id);
            let copy = self.copy.get(&tweak.id);
            let title = copy
                .filter(|c| !c.title.is_empty())
                .map_or(tweak.title.as_str(), |c| c.title.as_str());
            let summary = copy.filter(|c| !c.summary.is_empty()).map_or("", |c| c.summary.as_str());
            let id_for_click = tweak.id.clone();
            let pos = pending_rows.len();
            pending_rows.push(
                div()
                    .id(("opt-item", idx))
                    .role(Role::CheckBox)
                    .aria_label(title.to_owned())
                    .aria_toggled(if checked { Toggled::True } else { Toggled::False })
                    .tab_index(0)
                    .mx(px(20.))
                    .py(px(12.))
                    .when(pos > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
                    .flex()
                    .items_center()
                    .gap(px(14.))
                    .cursor_pointer()
                    .hover(|s| s.bg(a(0x1B182480)))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(kit::check_box(checked, false))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .child(kit::row_title(title.to_owned()))
                            .when(!summary.is_empty(), |d| {
                                d.child(kit::body(summary.to_owned()).text_color(c(INK_MUTED)))
                            }),
                    )
                    .when(tweak.restart, |d| {
                        d.child(kit::caption("Requer reinício").text_color(c(WARN)))
                    })
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.toggle_level_item(id_for_click.clone(), cx);
                    }))
                    .into_any_element(),
            );
        }

        let (sel_name, _, _) = level_meta(selected);
        let plan_heading = if is_custom {
            format!("Personalizado · base {sel_name}")
        } else {
            format!("Plano {sel_name}")
        };
        let apply_label = if all_done {
            "Já aplicado".to_owned()
        } else if effective_to_apply.is_empty() {
            "Nenhum item marcado".to_owned()
        } else if is_custom {
            format!("Aplicar {} marcado(s)", effective_to_apply.len())
        } else {
            format!("Aplicar {sel_name} ({})", effective_to_apply.len())
        };
        let apply_disabled = effective_to_apply.is_empty();

        let plan_body: AnyElement = if pending_rows.is_empty() {
            div()
                .w_full()
                .min_w_0()
                .px(px(20.))
                .py(px(22.))
                .flex()
                .items_start()
                .gap(px(12.))
                .text_color(c(OK))
                .child(div().pt(px(2.)).child(kit::glyph("\u{E73E}", 18.)))
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .gap(px(2.))
                        .child(kit::row_title(format!("Tudo do nível {sel_name} já está ativo neste PC.")))
                        .child(kit::body(
                            "Expanda \"Já feito pelo Vanta\" abaixo ou use o botão Desfazer para devolver os valores anteriores.",
                        )),
                )
                .into_any_element()
        } else {
            div().flex().flex_col().pb(px(6.)).children(pending_rows).into_any_element()
        };

        let undo_count = undo_ids.len();
        let plan_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(20.))
                    .py(px(16.))
                    .border_b_1()
                    .border_color(c(HAIRLINE))
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::section_title(plan_heading))
                            .child(kit::caption(format!(
                                "{} para aplicar · {} já feitos pelo Vanta{}{}",
                                effective_to_apply.len(),
                                effective_ja_feito.len(),
                                if active_plan.pulados.is_empty() {
                                    String::new()
                                } else {
                                    format!(" · {} pulado(s)", active_plan.pulados.len())
                                },
                                if effective_restart { " · pede reinício ao final" } else { "" }
                            ))),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_wrap()
                            .items_center()
                            .gap(px(8.))
                            .when(is_custom, |d| {
                                d.child(
                                    kit::button(
                                        "opt-reset-custom",
                                        "Voltar ao padrão do nível",
                                        Kind::Ghost,
                                        Some("\u{E777}"),
                                        false,
                                    )
                                    .on_click(cx.listener(|this, _, _, cx| this.reset_level_customization(cx))),
                                )
                            })
                            .when(undo_count > 0, |d| {
                                let ids_undo = undo_ids.clone();
                                d.child(
                                    kit::button(
                                        "opt-undo-journal",
                                        format!("Desfazer ({undo_count})"),
                                        Kind::Secondary,
                                        Some("\u{E7A7}"),
                                        false,
                                    )
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.undo_journal_ids(ids_undo.clone(), cx);
                                    })),
                                )
                            })
                            .child(
                                kit::button(
                                    "opt-apply",
                                    apply_label,
                                    Kind::Primary,
                                    Some(if all_done { "\u{E73E}" } else { "\u{E945}" }),
                                    apply_disabled,
                                )
                                .on_click(cx.listener(|this, _, _, cx| this.apply_selected_level(cx))),
                            ),
                    ),
            )
            .child(plan_body);

        // Seção recolhida "Já feito pelo Vanta (N)"
        let ja_feito_open = self.ja_feito_open;
        let ja_feito_count = effective_ja_feito.len();
        let ja_feito_rows: Vec<AnyElement> = if ja_feito_open {
            effective_ja_feito
                .iter()
                .enumerate()
                .map(|(idx, id)| {
                    let tweak = self.tweaks.iter().find(|t| &t.id == id);
                    let copy = self.copy.get(id);
                    let title = copy
                        .filter(|c| !c.title.is_empty())
                        .map(|c| c.title.clone())
                        .or_else(|| tweak.map(|t| t.title.clone()))
                        .unwrap_or_else(|| id.clone());
                    let summary = copy.map(|c| c.summary.clone()).unwrap_or_default();
                    let area = tweak.map(|t| t.category.clone()).unwrap_or_default();
                    let in_journal = self.diario.entrada(id).is_some();
                    let id_undo = id.clone();
                    div()
                        .id(("ja-feito", idx))
                        .mx(px(20.))
                        .py(px(10.))
                        .border_t_1()
                        .border_color(c(HAIRLINE))
                        .flex()
                        .items_center()
                        .justify_between()
                        .gap(px(12.))
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .flex()
                                .items_center()
                                .gap(px(10.))
                                .child(div().text_color(c(OK)).child(kit::glyph("\u{E73E}", 12.)))
                                .child(
                                    div()
                                        .flex_1()
                                        .min_w_0()
                                        .flex()
                                        .flex_col()
                                        .child(kit::row_title(title))
                                        .when(!summary.is_empty(), |d| d.child(kit::caption(summary))),
                                ),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(8.))
                                .when(in_journal, |d| {
                                    d.child(
                                        kit::link(("ja-feito-undo", idx), "Desfazer", false).on_click(
                                            cx.listener(move |this, _, _, cx| {
                                                this.undo_journal_ids(vec![id_undo.clone()], cx);
                                            }),
                                        ),
                                    )
                                })
                                .when(!area.is_empty(), |d| {
                                    let area_click = area.clone();
                                    d.child(
                                        kit::link(("ja-feito-go", idx), "Ver manual", false).on_click(
                                            cx.listener(move |this, _, _, cx| {
                                                if area_click == "Avancado" {
                                                    this.go_page(Page::Advanced);
                                                } else {
                                                    this.go_settings(&area_click);
                                                }
                                                cx.notify();
                                            }),
                                        ),
                                    )
                                }),
                        )
                        .into_any_element()
                })
                .collect()
        } else {
            Vec::new()
        };

        let ja_feito_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .id("opt-ja-feito-toggle")
                    .role(Role::Button)
                    .aria_label(format!("Já feito pelo Vanta ({ja_feito_count})"))
                    .aria_expanded(ja_feito_open)
                    .tab_index(0)
                    .px(px(20.))
                    .py(px(14.))
                    .flex()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .cursor_pointer()
                    .hover(|s| s.bg(a(0x1B182480)))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_wrap()
                            .items_center()
                            .gap(px(10.))
                            .child(div().text_color(c(OK)).child(kit::glyph("\u{E73E}", 14.)))
                            .child(kit::row_title(format!("Já feito pelo Vanta ({ja_feito_count})")))
                            .child(kit::caption("— ativos no registro deste PC")),
                    )
                    .child(
                        div()
                            .text_color(c(INK_SUBTLE))
                            .child(kit::glyph(if ja_feito_open { "\u{E70E}" } else { "\u{E70D}" }, 12.)),
                    )
                    .on_click(cx.listener(|this, _, _, cx| {
                        this.ja_feito_open = !this.ja_feito_open;
                        cx.notify();
                    })),
            )
            .when(ja_feito_open && ja_feito_rows.is_empty(), |d| {
                d.child(
                    div()
                        .mx(px(20.))
                        .py(px(12.))
                        .border_t_1()
                        .border_color(c(HAIRLINE))
                        .child(kit::body("Nenhum ajuste deste nível está ativo ainda.")),
                )
            })
            .when(ja_feito_open && !ja_feito_rows.is_empty(), |d| {
                d.child(div().pb(px(6.)).children(ja_feito_rows))
            });

        // Seção "Visual Vanta" (3 papéis de parede 2K finalistas)
        let wp_cards: Vec<AnyElement> = kit::BACKGROUNDS
            .iter()
            .enumerate()
            .map(|(i, (key, name, _))| {
                let key_owned = (*key).to_owned();
                let is_sel = self.prefs.background == *key;
                div()
                    .id(("opt-wp", i))
                    .role(Role::RadioButton)
                    .aria_label(format!("Papel de parede {name}"))
                    .aria_selected(is_sel)
                    .tab_index(0)
                    .w(px(236.))
                    .flex()
                    .flex_col()
                    .gap(px(8.))
                    .cursor_pointer()
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(
                        div()
                            .relative()
                            .h(px(132.))
                            .rounded(px(10.))
                            .border_2()
                            .border_color(if is_sel { c(ACCENT_HOVER) } else { c(HAIRLINE_STRONG) })
                            .child(
                                img(kit::background_image(&key_owned))
                                    .size_full()
                                    .rounded(px(8.))
                                    .object_fit(ObjectFit::Cover),
                            )
                            .when(is_sel, |d| {
                                d.child(
                                    div()
                                        .absolute()
                                        .top(px(8.))
                                        .right(px(8.))
                                        .size(px(22.))
                                        .rounded(px(11.))
                                        .flex()
                                        .items_center()
                                        .justify_center()
                                        .bg(c(ACCENT))
                                        .text_color(c(0xFFFFFF))
                                        .child(kit::glyph("\u{E73E}", 10.)),
                                )
                            }),
                    )
                    .child(
                        kit::caption(format!("0{} · {name}", i + 1))
                            .text_color(if is_sel { c(INK) } else { c(INK_MUTED) }),
                    )
                    .on_click(cx.listener(move |this, _, _, cx| {
                        this.prefs.background.clone_from(&key_owned);
                        this.prefs.save();
                        cx.notify();
                    }))
                    .into_any_element()
            })
            .collect();

        let visual_panel = kit::panel()
            .p(px(20.))
            .flex()
            .flex_col()
            .gap(px(14.))
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(8.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .child(kit::section_title("Visual Vanta"))
                            .child(kit::body(
                                "Tema escuro, destaque #7C4EE0 e os 3 papéis de parede 2K assinados do Vanta.",
                            )),
                    )
                    .child(kit::badge("\u{E790}", "Padrão ativo")),
            )
            .child(div().flex().flex_wrap().gap(px(14.)).children(wp_cards));

        let mut body = div()
            .w_full()
            .min_w_0()
            .max_w(px(1060.))
            .flex()
            .flex_col()
            .gap(px(22.))
            .child(self.header(
                "Otimizar",
                "Escolha um nível pronto ou personalize os itens. O Vanta lê o registro real, grava o estado anterior no diário e aplica só o que falta.",
            ))
            .child(hw_status)
            .child(div().flex().flex_wrap().gap(px(14.)).children(level_cards));
        if !notices.is_empty() {
            body = body.child(div().w_full().min_w_0().flex().flex_col().gap(px(10.)).children(notices));
        }
        body = body.child(plan_panel).child(ja_feito_panel);

        if !active_plan.pulados.is_empty() {
            let pulados_open = self.pulados_open;
            let count = active_plan.pulados.len();
            let rows: Vec<AnyElement> = active_plan
                .pulados
                .iter()
                .map(|(id, reason)| {
                    let title = self
                        .copy
                        .get(id)
                        .filter(|c| !c.title.is_empty())
                        .map(|c| c.title.as_str())
                        .unwrap_or(id.as_str());
                    div()
                        .flex()
                        .flex_wrap()
                        .items_baseline()
                        .gap(px(6.))
                        .child(kit::caption(format!("• {title}")).text_color(c(INK_MUTED)))
                        .child(kit::caption(format!("— {reason}")).text_color(c(WARN)))
                        .into_any_element()
                })
                .collect();
            body = body.child(
                kit::panel()
                    .flex()
                    .flex_col()
                    .child(
                        div()
                            .id("opt-pulados-toggle")
                            .role(Role::Button)
                            .aria_label(format!("Pulados neste PC ({count})"))
                            .aria_expanded(pulados_open)
                            .tab_index(0)
                            .px(px(20.))
                            .py(px(13.))
                            .flex()
                            .items_center()
                            .justify_between()
                            .cursor_pointer()
                            .hover(|s| s.bg(a(0x1B182480)))
                            .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                            .child(
                                div()
                                    .flex_1()
                                    .min_w_0()
                                    .flex()
                                    .flex_wrap()
                                    .items_center()
                                    .gap(px(8.))
                                    .child(div().text_color(c(WARN)).child(kit::glyph("\u{E7BA}", 13.)))
                                    .child(kit::row_title(format!("Pulados neste PC ({count})")))
                                    .child(kit::caption("— não se aplicam ao hardware ou edição atual")),
                            )
                            .child(kit::glyph(if pulados_open { "\u{E70E}" } else { "\u{E70D}" }, 11.))
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.pulados_open = !this.pulados_open;
                                cx.notify();
                            })),
                    )
                    .when(pulados_open, |d| {
                        d.child(
                            div()
                                .mx(px(20.))
                                .py(px(12.))
                                .border_t_1()
                                .border_color(c(HAIRLINE))
                                .flex()
                                .flex_col()
                                .gap(px(6.))
                                .children(rows),
                        )
                    }),
            );
        }

        body = body.child(visual_panel);
        self.page_scroll(Page::Optimize, body.into_any_element(), 72., None)
    }

    // ---------- Páginas Manuais v1.1 (Energia, Apps, Serviços, Avançado) ----------

    pub(super) fn manual_page(&mut self, page: Page, cx: &mut Context<Self>) -> AnyElement {
        match page {
            Page::Power => self.power_page(cx),
            Page::Services => self.services_page(cx),
            Page::Apps => self.apps_page(cx),
            Page::Advanced => self.advanced_page(cx),
            _ => self.optimize(cx),
        }
    }

    fn power_page(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let busy = self.power_busy;
        let has_journal = self.diario.entrada("energia").is_some();
        let has_plan_selected = self.power_selected.contains(&OpcaoEnergia::PlanoVanta);

        let option_rows: Vec<AnyElement> = OpcaoEnergia::TODAS
            .into_iter()
            .enumerate()
            .map(|(idx, op)| {
                let checked = self.power_selected.contains(&op);
                let (title, desc) = power_option_copy(op);
                let aviso = op.aviso();
                let is_cpu_100 = op == OpcaoEnergia::CpuMinima100;
                div()
                    .id(("pwr-op", idx))
                    .role(Role::CheckBox)
                    .aria_label(title)
                    .aria_toggled(if checked { Toggled::True } else { Toggled::False })
                    .tab_index(0)
                    .mx(px(20.))
                    .py(px(14.))
                    .min_w_0()
                    .when(idx > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
                    .flex()
                    .items_start()
                    .gap(px(14.))
                    .cursor_pointer()
                    .hover(|s| s.bg(a(0x1B182480)))
                    .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                    .child(div().pt(px(2.)).child(kit::check_box(checked, false)))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(4.))
                            .child(
                                div()
                                    .flex()
                                    .flex_wrap()
                                    .items_center()
                                    .gap(px(8.))
                                    .child(kit::row_title(title))
                                    .child(kit::mono(op.id(), 11.5)),
                            )
                            .child(kit::body(desc).text_color(c(INK_MUTED)))
                            .when(!aviso.is_empty(), |d| {
                                d.child(
                                    div()
                                        .w_full()
                                        .min_w_0()
                                        .mt(px(4.))
                                        .px(px(10.))
                                        .py(px(6.))
                                        .rounded(px(8.))
                                        .border_1()
                                        .border_color(if is_cpu_100 { a(0xFBBF2466) } else { a(0xFBBF2438) })
                                        .bg(if is_cpu_100 { a(0x241D11F0) } else { a(0x1B1715E6) })
                                        .flex()
                                        .items_start()
                                        .gap(px(8.))
                                        .text_color(c(WARN))
                                        .child(div().pt(px(2.)).child(kit::glyph("\u{E7BA}", 12.)))
                                        .child(
                                            kit::caption(aviso)
                                                .flex_1()
                                                .min_w_0()
                                                .text_color(if is_cpu_100 { c(WARN) } else { c(INK_MUTED) }),
                                        ),
                                )
                            }),
                    )
                    .on_click(cx.listener(move |this, _, _, cx| this.toggle_power_option(op, cx)))
                    .into_any_element()
            })
            .collect();

        let mut power_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(20.))
                    .py(px(16.))
                    .border_b_1()
                    .border_color(c(HAIRLINE))
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::section_title("Plano de energia Vanta (AC)"))
                            .child(kit::caption(if has_journal {
                                "Plano anterior salvo no diário · tempo de tela, suspensão, bateria e USB preservados"
                            } else {
                                "Cria cópia do seu plano atual; nunca altera tempo de tela, suspensão nem bateria"
                            })),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.))
                            .when(has_journal, |d| {
                                d.child(
                                    kit::button("pwr-undo", "Desfazer plano Vanta", Kind::Secondary, Some("\u{E7A7}"), busy)
                                        .on_click(cx.listener(|this, _, _, cx| this.start_power_undo(cx))),
                                )
                            })
                            .child(
                                kit::button(
                                    "pwr-apply",
                                    if busy { "Aplicando…" } else { "Aplicar opções" },
                                    Kind::Primary,
                                    Some("\u{E83F}"),
                                    busy || !has_plan_selected,
                                )
                                .on_click(cx.listener(|this, _, _, cx| this.start_power_apply(cx))),
                            ),
                    ),
            )
            .children(option_rows);

        if busy {
            power_panel = power_panel.child(
                div()
                    .mx(px(20.))
                    .py(px(10.))
                    .border_t_1()
                    .border_color(c(HAIRLINE))
                    .child(kit::caption("Executando powercfg e atualizando o diário…")),
            );
        }

        let mut extra_notices: Vec<AnyElement> = Vec::new();
        for w in &self.power_warnings {
            extra_notices.push(Self::alert_box(WARN, "\u{E7BA}", w.clone(), None));
        }
        if let Some(fb) = &self.power_feedback {
            match fb {
                Ok(msg) => extra_notices.push(Self::alert_box(OK, "\u{E73E}", msg.clone(), None)),
                Err(err) => extra_notices.push(Self::alert_box(ERR, "\u{EA39}", err.clone(), None)),
            }
        }

        let mut body = self.manual_shell_top(
            Page::Power,
            "Energia",
            "Plano de energia Vanta na tomada, opções avançadas de processador e hibernação. O plano anterior é salvo no diário para Desfazer.",
            cx,
        );
        if !extra_notices.is_empty() {
            body = body.child(div().w_full().min_w_0().flex().flex_col().gap(px(8.)).children(extra_notices));
        }
        body = body.child(power_panel).child(self.manual_tweaks_section(Page::Power, "Ajustes de energia no registro", cx));
        self.page_scroll(Page::Power, body.into_any_element(), 72., None)
    }

    fn services_page(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let mut denied_errors: Vec<String> = Vec::new();
        let svc_rows: Vec<AnyElement> = SERVICOS
            .iter()
            .enumerate()
            .map(|(idx, svc)| {
                let estado = self
                    .service_states
                    .get(svc.nome)
                    .cloned()
                    .unwrap_or(Ok(EstadoServico::Ausente));
                let current = self.service_current.get(svc.nome).copied().flatten();
                let denied_msg = estado.as_ref().err().cloned();
                if let Some(err) = &denied_msg {
                    denied_errors.push(err.clone());
                }
                let absent = matches!(estado, Ok(EstadoServico::Ausente) | Err(_));
                let status_pill: AnyElement = match &estado {
                    Ok(EstadoServico::JaFeito) => div()
                        .px(px(8.))
                        .py(px(2.))
                        .rounded(px(999.))
                        .bg(a(0x4ADE8024))
                        .child(kit::caption("Já feito pelo Vanta").text_color(c(OK)))
                        .into_any_element(),
                    Ok(EstadoServico::Ausente) => div()
                        .px(px(8.))
                        .py(px(2.))
                        .rounded(px(999.))
                        .bg(c(SURFACE2))
                        .child(kit::caption("Ausente neste Windows"))
                        .into_any_element(),
                    Ok(EstadoServico::Falta { atual }) => div()
                        .px(px(8.))
                        .py(px(2.))
                        .rounded(px(999.))
                        .bg(c(SURFACE2))
                        .child(kit::caption(format!("Atual: {}", start_type_label(*atual))).text_color(c(INK_MUTED)))
                        .into_any_element(),
                    Err(_) => div()
                        .px(px(8.))
                        .py(px(2.))
                        .rounded(px(999.))
                        .bg(a(0xF8717126))
                        .child(kit::caption("Acesso negado").text_color(c(ERR)))
                        .into_any_element(),
                };

                let seg_btns: Vec<AnyElement> = [StartType::Auto, StartType::Manual, StartType::Disabled]
                    .into_iter()
                    .enumerate()
                    .map(|(s_idx, target)| {
                        let active = current == Some(target);
                        let svc_name = svc.nome;
                        div()
                            .id(("svc-mode", idx * 4 + s_idx))
                            .role(Role::RadioButton)
                            .aria_label(format!("{} {}", svc.titulo, start_type_label(target)))
                            .aria_selected(active)
                            .aria_disabled(absent)
                            .px(px(10.))
                            .h(px(28.))
                            .rounded(px(6.))
                            .flex()
                            .items_center()
                            .border_1()
                            .border_color(if active { c(ACCENT) } else { c(HAIRLINE) })
                            .bg(if active { a(0x7C4EE029) } else { c(SURFACE2) })
                            .font_family(FONT_TEXT)
                            .font_weight(FontWeight::MEDIUM)
                            .text_size(px(12.))
                            .text_color(if active { c(INK) } else { c(INK_MUTED) })
                            .map(|d| {
                                if absent {
                                    d.opacity(0.4)
                                } else {
                                    d.cursor_pointer()
                                        .tab_index(0)
                                        .hover(|s| s.border_color(c(HAIRLINE_STRONG)).text_color(c(INK)))
                                        .focus_visible(|s| focus_ring(s, c(0xA78BFE), c(CANVAS)))
                                        .on_click(cx.listener(move |this, _, _, cx| {
                                            this.set_service_start(svc_name, target, cx);
                                        }))
                                }
                            })
                            .child(start_type_label(target))
                            .into_any_element()
                    })
                    .collect();

                let at_default = current == Some(svc.padrao);
                let svc_name = svc.nome;
                div()
                    .id(("svc-row", idx))
                    .mx(px(20.))
                    .py(px(13.))
                    .when(idx > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .min_w(px(260.))
                            .flex()
                            .flex_col()
                            .gap(px(4.))
                            .child(
                                div()
                                    .flex()
                                    .flex_wrap()
                                    .items_center()
                                    .gap(px(8.))
                                    .child(kit::row_title(svc.titulo))
                                    .child(kit::mono(svc.nome, 11.5))
                                    .child(status_pill),
                            )
                            .child(kit::caption(format!(
                                "Padrão do Windows: {}{}",
                                start_type_label(svc.padrao),
                                if svc.equilibrado { " · incluído no Equilibrado (Manual)" } else { " · controle manual" }
                            )))
                            .when_some(denied_msg, |d, msg| {
                                d.child(kit::caption(msg).w_full().min_w_0().text_color(c(ERR)))
                            }),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_wrap()
                            .items_center()
                            .gap(px(6.))
                            .children(seg_btns)
                            .child(
                                kit::button(
                                    ("svc-def", idx),
                                    "Voltar ao padrão",
                                    Kind::Ghost,
                                    None,
                                    absent || at_default,
                                )
                                .on_click(cx.listener(move |this, _, _, cx| {
                                    this.reset_service_default(svc_name, cx);
                                })),
                            ),
                    )
                    .into_any_element()
            })
            .collect();

        let services_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(20.))
                    .py(px(16.))
                    .border_b_1()
                    .border_color(c(HAIRLINE))
                    .flex()
                    .flex_col()
                    .gap(px(3.))
                    .child(kit::section_title("Modo de inicialização por serviço"))
                    .child(kit::caption(
                        "Altera apenas o valor Start, preservando gatilhos e atraso. Impressora, Bluetooth, Busca, Rede e Defender são protegidos.",
                    )),
            )
            .children(svc_rows);

        let mut body = self.manual_shell_top(
            Page::Services,
            "Serviços",
            "Controle individual de serviços opcionais com leitura real do registro e restauração para o padrão do Windows.",
            cx,
        );
        if !denied_errors.is_empty() {
            body = body.child(Self::alert_box(
                ERR,
                "\u{EA39}",
                format!(
                    "O Windows negou a leitura de {} serviço(s) no gerenciador de serviços. Abra o Vanta Tools como administrador para consultar e alterar.",
                    denied_errors.len()
                ),
                None,
            ));
        }
        if let Some(fb) = &self.service_feedback {
            match fb {
                Ok(msg) => body = body.child(Self::alert_box(OK, "\u{E73E}", msg.clone(), None)),
                Err(err) => body = body.child(Self::alert_box(ERR, "\u{EA39}", err.clone(), None)),
            }
        }
        body = body
            .child(services_panel)
            .child(self.manual_tweaks_section(Page::Services, "Ajustes de serviços no catálogo", cx));
        self.page_scroll(Page::Services, body.into_any_element(), 72., None)
    }

    fn apps_page(&mut self, cx: &mut Context<Self>) -> AnyElement {
        if self.app_states.is_none() && !self.apps_loading {
            self.load_apps_in_background();
        }
        let loading = self.apps_loading && self.app_states.is_none();
        let busy_chave = self.app_busy.clone();

        let protected_names: String = PROTEGIDOS
            .iter()
            .map(|(pkg, reason)| format!("• {pkg}: {reason}"))
            .collect::<Vec<_>>()
            .join("\n");

        let info_panel = kit::panel()
            .p(px(16.))
            .flex()
            .flex_col()
            .gap(px(6.))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(8.))
                    .text_color(c(ACCENT_TEXT))
                    .child(kit::glyph("\u{E72E}", 14.))
                    .child(kit::row_title("Componentes protegidos (nunca removidos)")),
            )
            .child(kit::body(protected_names).w_full().min_w_0().text_color(c(INK_MUTED)))
            .child(kit::caption(NOTA_REINSTALAR).w_full().min_w_0().text_color(c(WARN)));

        let app_rows: AnyElement = if loading {
            div()
                .px(px(20.))
                .py(px(24.))
                .flex()
                .items_center()
                .gap(px(10.))
                .text_color(c(INK_MUTED))
                .child(kit::glyph("\u{E895}", 14.))
                .child(kit::body("Verificando estado dos apps instalados neste usuário…"))
                .into_any_element()
        } else {
            let rows: Vec<AnyElement> = apps::APPS
                .iter()
                .enumerate()
                .map(|(idx, app)| {
                    let st = self
                        .app_states
                        .as_ref()
                        .and_then(|m| m.get(app.chave))
                        .cloned()
                        .unwrap_or(EstadoApp::Desconhecido);
                    let is_busy = busy_chave.as_deref() == Some(app.chave);
                    let any_busy = busy_chave.is_some();
                    let (badge_label, badge_bg, badge_fg) = match st {
                        EstadoApp::Instalado => ("Instalado", 0x4ADE8024, OK),
                        EstadoApp::Removido => ("Removido", 0x221E2CFF, INK_MUTED),
                        EstadoApp::Desconhecido => ("Estado desconhecido", 0xFBBF2420, WARN),
                    };
                    let chave_rm = app.chave.to_owned();
                    let chave_re = app.chave.to_owned();
                    div()
                        .id(("vanta-app", idx))
                        .mx(px(20.))
                        .py(px(14.))
                        .when(idx > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
                        .flex()
                        .flex_wrap()
                        .items_center()
                        .justify_between()
                        .gap(px(12.))
                        .child(
                            div()
                                .flex_1()
                                .min_w(px(280.))
                                .flex()
                                .flex_col()
                                .gap(px(4.))
                                .child(
                                    div()
                                        .flex()
                                        .flex_wrap()
                                        .items_center()
                                        .gap(px(8.))
                                        .child(kit::row_title(app.nome))
                                        .child(kit::mono(format!("{} · {}", app.fonte.id(), app.id), 11.5))
                                        .child(
                                            div()
                                                .px(px(8.))
                                                .py(px(2.))
                                                .rounded(px(999.))
                                                .bg(a(badge_bg))
                                                .child(kit::caption(badge_label).text_color(c(badge_fg))),
                                        ),
                                )
                                .child(kit::body(app.aviso).text_color(c(INK_MUTED))),
                        )
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(8.))
                                .child(
                                    kit::button(
                                        ("app-rm", idx),
                                        if is_busy { "Executando…" } else { "Remover" },
                                        Kind::Secondary,
                                        Some("\u{E74D}"),
                                        any_busy || st == EstadoApp::Removido,
                                    )
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.start_app_action(chave_rm.clone(), true, cx);
                                    })),
                                )
                                .child(
                                    kit::button(
                                        ("app-re", idx),
                                        ROTULO_REINSTALAR,
                                        Kind::Ghost,
                                        Some("\u{E896}"),
                                        any_busy || st == EstadoApp::Instalado,
                                    )
                                    .on_click(cx.listener(move |this, _, _, cx| {
                                        this.start_app_action(chave_re.clone(), false, cx);
                                    })),
                                ),
                        )
                        .into_any_element()
                })
                .collect();
            div().flex().flex_col().children(rows).into_any_element()
        };

        let apps_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(20.))
                    .py(px(16.))
                    .border_b_1()
                    .border_color(c(HAIRLINE))
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::section_title("Apps opcionais (somente usuário atual)"))
                            .child(kit::caption(
                                "Remove apenas no seu usuário via Appx/winget. A Microsoft Store e o App Installer nunca são removidos.",
                            )),
                    )
                    .child(
                        kit::button("apps-refresh", "Atualizar", Kind::Ghost, Some("\u{E72C}"), self.apps_loading)
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.app_states = None;
                                this.load_apps_in_background();
                                cx.notify();
                            })),
                    ),
            )
            .child(app_rows);

        let mut body = self.manual_shell_top(
            Page::Apps,
            "Apps",
            "Gerenciamento individual de apps opcionais do Windows no escopo do usuário atual, preservando Microsoft Store e App Installer.",
            cx,
        );
        if let Some(fb) = &self.app_feedback {
            match fb {
                Ok(msg) => body = body.child(Self::alert_box(OK, "\u{E73E}", msg.clone(), None)),
                Err(err) => body = body.child(Self::alert_box(ERR, "\u{EA39}", err.clone(), None)),
            }
        }
        body = body
            .child(info_panel)
            .child(apps_panel)
            .child(self.manual_tweaks_section(Page::Apps, "Ajustes de apps no registro", cx));
        self.page_scroll(Page::Apps, body.into_any_element(), 72., None)
    }

    fn advanced_page(&mut self, cx: &mut Context<Self>) -> AnyElement {
        if self.devices_state.is_none() && !self.devices_loading {
            self.load_devices_in_background();
        }
        let busy_id = self.device_busy.clone();
        let show_all = self.devices_show_all;

        let devices_body: AnyElement = match &self.devices_state {
            None => div()
                .px(px(20.))
                .py(px(24.))
                .flex()
                .items_center()
                .gap(px(10.))
                .text_color(c(INK_MUTED))
                .child(kit::glyph("\u{E895}", 14.))
                .child(kit::body("Lendo inventário PnP do Windows…"))
                .into_any_element(),
            Some(Err(err)) => div()
                .w_full()
                .min_w_0()
                .px(px(20.))
                .py(px(18.))
                .flex()
                .flex_wrap()
                .items_start()
                .justify_between()
                .gap(px(12.))
                .child(
                    kit::body(format!("Não foi possível ler o inventário de dispositivos: {err}"))
                        .flex_1()
                        .min_w(px(240.))
                        .text_color(c(ERR)),
                )
                .child(
                    kit::button("dev-retry", "Tentar de novo", Kind::Secondary, Some("\u{E72C}"), self.devices_loading)
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.devices_state = None;
                            this.load_devices_in_background();
                            cx.notify();
                        })),
                )
                .into_any_element(),
            Some(Ok(list)) => {
                let filtered: Vec<&Dispositivo> = list
                    .iter()
                    .filter(|d| {
                        show_all
                            || !avancado::protegido(d)
                            || self.diario.entrada(&format!("pnp:{}", d.instance_id)).is_some()
                    })
                    .take(80)
                    .collect();
                if filtered.is_empty() {
                    div()
                        .px(px(20.))
                        .py(px(22.))
                        .flex()
                        .flex_col()
                        .gap(px(4.))
                        .child(kit::row_title("Nenhum dispositivo opcional elegível encontrado"))
                        .child(kit::body(format!(
                            "O inventário leu {} dispositivo(s), todos de classes protegidas (vídeo, rede, disco, teclado, mouse, etc.).",
                            list.len()
                        )))
                        .into_any_element()
                } else {
                    let rows: Vec<AnyElement> = filtered
                        .into_iter()
                        .enumerate()
                        .map(|(idx, dev)| {
                            let protected = avancado::protegido(dev);
                            let in_journal = self.diario.entrada(&format!("pnp:{}", dev.instance_id)).is_some();
                            let is_busy = busy_id.as_deref() == Some(dev.instance_id.as_str());
                            let any_busy = busy_id.is_some();
                            let id_click = dev.instance_id.clone();
                            let active = dev.ativo;
                            div()
                                .id(("pnp-dev", idx))
                                .mx(px(20.))
                                .py(px(12.))
                                .when(idx > 0, |d| d.border_t_1().border_color(c(HAIRLINE)))
                                .flex()
                                .flex_wrap()
                                .items_center()
                                .justify_between()
                                .gap(px(12.))
                                .child(
                                    div()
                                        .flex_1()
                                        .min_w(px(280.))
                                        .flex()
                                        .flex_col()
                                        .gap(px(3.))
                                        .child(
                                            div()
                                                .flex()
                                                .flex_wrap()
                                                .items_center()
                                                .gap(px(8.))
                                                .child(kit::row_title(dev.nome.clone()))
                                                .child(
                                                    div()
                                                        .px(px(7.))
                                                        .py(px(1.))
                                                        .rounded(px(999.))
                                                        .bg(c(SURFACE2))
                                                        .child(kit::caption(dev.classe.clone())),
                                                )
                                                .when(protected, |d| {
                                                    d.child(
                                                        div()
                                                            .px(px(7.))
                                                            .py(px(1.))
                                                            .rounded(px(999.))
                                                            .bg(a(0xFBBF2420))
                                                            .child(kit::caption("Protegido").text_color(c(WARN))),
                                                    )
                                                })
                                                .when(in_journal, |d| {
                                                    d.child(
                                                        div()
                                                            .px(px(7.))
                                                            .py(px(1.))
                                                            .rounded(px(999.))
                                                            .bg(a(0x7C4EE029))
                                                            .child(kit::caption("No diário").text_color(c(ACCENT_TEXT))),
                                                    )
                                                }),
                                        )
                                        .child(kit::mono(dev.instance_id.clone(), 11.)),
                                )
                                .child(
                                    div()
                                        .flex()
                                        .items_center()
                                        .gap(px(8.))
                                        .child(kit::caption(if active { "Ativo" } else { "Desligado" }).text_color(if active { c(OK) } else { c(INK_SUBTLE) }))
                                        .when(!protected || !active || in_journal, |d| {
                                            d.child(
                                                kit::button(
                                                    ("pnp-act", idx),
                                                    if is_busy {
                                                        "Executando…"
                                                    } else if active {
                                                        "Desligar"
                                                    } else {
                                                        "Religar"
                                                    },
                                                    if active { Kind::Secondary } else { Kind::Primary },
                                                    None,
                                                    any_busy || (active && protected),
                                                )
                                                .on_click(cx.listener(move |this, _, _, cx| {
                                                    this.start_device_action(id_click.clone(), active, cx);
                                                })),
                                            )
                                        }),
                                )
                                .into_any_element()
                        })
                        .collect();
                    div().flex().flex_col().pb(px(6.)).children(rows).into_any_element()
                }
            }
        };

        let devices_panel = kit::panel()
            .flex()
            .flex_col()
            .child(
                div()
                    .px(px(20.))
                    .py(px(16.))
                    .border_b_1()
                    .border_color(c(HAIRLINE))
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(3.))
                            .child(kit::section_title("Dispositivos PnP (escolha individual por InstanceId)"))
                            .child(kit::caption(
                                "Nenhum nível desliga dispositivos automaticamente. Classes críticas são recusadas e cada alteração fica no diário.",
                            )),
                    )
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(8.))
                            .child(
                                kit::button(
                                    "dev-filter",
                                    if show_all { "Só elegíveis" } else { "Ver inventário completo" },
                                    Kind::Ghost,
                                    None,
                                    false,
                                )
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.devices_show_all = !this.devices_show_all;
                                    cx.notify();
                                })),
                            )
                            .child(
                                kit::button("dev-refresh", "Atualizar", Kind::Ghost, Some("\u{E72C}"), self.devices_loading)
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.devices_state = None;
                                        this.load_devices_in_background();
                                        cx.notify();
                                    })),
                            ),
                    ),
            )
            .child(devices_body);

        let mut body = self.manual_shell_top(
            Page::Advanced,
            "Avançado",
            "Ajustes avançados do registro e controle manual individual de dispositivos PnP por InstanceId (sem disable-pnp automático).",
            cx,
        );
        if let Some(fb) = &self.device_feedback {
            match fb {
                Ok(msg) => body = body.child(Self::alert_box(OK, "\u{E73E}", msg.clone(), None)),
                Err(err) => body = body.child(Self::alert_box(ERR, "\u{EA39}", err.clone(), None)),
            }
        }
        body = body
            .child(devices_panel)
            .child(self.manual_tweaks_section(Page::Advanced, "Ajustes avançados no registro", cx));
        self.page_scroll(Page::Advanced, body.into_any_element(), 72., None)
    }

    fn manual_shell_top(
        &self,
        page: Page,
        title: &'static str,
        lead: &'static str,
        cx: &mut Context<Self>,
    ) -> gpui::Div {
        let (on_count, total) = self.manual_counts(page);
        let mut top = div()
            .w_full()
            .min_w_0()
            .max_w(px(980.))
            .flex()
            .flex_col()
            .gap(px(20.))
            .child(self.header(title, lead))
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .gap(px(16.))
                    .child(
                        div()
                            .flex()
                            .items_center()
                            .gap(px(10.))
                            .child(kit::meter(on_count as f32 / total.max(1) as f32, Some(76.)))
                            .child(kit::caption(format!("{on_count} de {total} ajustes de registro ativos"))),
                    )
                    .child(
                        kit::link("manual-back-opt", "Ver níveis em Otimizar", false).on_click(cx.listener(
                            |this, _, _, cx| {
                                this.go_page(Page::Optimize);
                                cx.notify();
                            },
                        )),
                    ),
            );
        if let Some(notice) = self.current_page_notice(page) {
            let (accent, icon) = match notice.kind {
                NoticeKind::Error => (ERR, "\u{EA39}"),
                NoticeKind::Info => (ACCENT_TEXT, "\u{E946}"),
            };
            top = top.child(Self::alert_box(accent, icon, notice.message.clone(), None));
        }
        top
    }

    fn manual_tweaks_section(&self, page: Page, heading: &'static str, cx: &mut Context<Self>) -> AnyElement {
        let indices = self.manual_tweak_indices(page);
        let rows: Vec<AnyElement> = indices
            .iter()
            .enumerate()
            .map(|(pos, &i)| self.tweak_row(pos, i, cx))
            .collect();
        if rows.is_empty() {
            kit::panel()
                .p(px(24.))
                .flex()
                .flex_col()
                .gap(px(4.))
                .child(kit::section_title(heading))
                .child(kit::body("Nenhum ajuste de registro disponível nesta edição."))
                .into_any_element()
        } else {
            kit::panel()
                .flex()
                .flex_col()
                .child(
                    div()
                        .px(px(20.))
                        .py(px(14.))
                        .border_b_1()
                        .border_color(c(HAIRLINE))
                        .child(kit::section_title(heading)),
                )
                .child(div().flex().flex_col().py(px(4.)).children(rows))
                .into_any_element()
        }
    }

    fn alert_box(accent: u32, icon: &'static str, message: String, trailing: Option<AnyElement>) -> AnyElement {
        let (border, bg) = match accent {
            OK => (a(0x4ADE8059), a(0x111F18F0)),
            ERR => (a(0xF8717166), a(0x211319F0)),
            WARN => (a(0xFBBF2459), a(0x211B11F0)),
            _ => (a(0xA78BFA59), a(0x1A1628F0)),
        };
        div()
            .w_full()
            .min_w_0()
            .px(px(16.))
            .py(px(12.))
            .rounded(px(10.))
            .border_1()
            .border_color(border)
            .bg(bg)
            .flex()
            .flex_wrap()
            .items_start()
            .justify_between()
            .gap(px(12.))
            .child(
                div()
                    .flex_1()
                    .min_w(px(220.))
                    .flex()
                    .items_start()
                    .gap(px(10.))
                    .text_color(c(accent))
                    .child(div().pt(px(3.)).child(kit::glyph(icon, 14.)))
                    .child(
                        kit::body(SharedString::from(message))
                            .flex_1()
                            .min_w_0()
                            .text_color(c(INK)),
                    ),
            )
            .children(trailing)
            .into_any_element()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::kit::{BACKGROUNDS, Prefs};
    use vanta_core::edicao::Edicao;
    use vanta_core::tweaks::RegValue;

    #[derive(Default)]
    struct EmptyStore;

    impl SystemStore for EmptyStore {
        fn get_value(&self, _: &str, _: &str) -> Option<RegValue> {
            None
        }
        fn set_value(&mut self, _: &str, _: &str, _: &str, _: RegValue) {}
        fn delete_value(&mut self, _: &str, _: &str) {}
        fn get_service_start(&self, _: &str) -> Option<String> {
            None
        }
        fn set_service_start(&mut self, _: &str, _: &str) {}
    }

    #[test]
    fn prefs_round_trip_persists_level_and_custom_state() {
        let legacy = r#"{ "Background": "torii", "DimWorkPages": false }"#;
        let parsed_legacy = Prefs::from_json_str(legacy);
        assert_eq!(parsed_legacy.background, "torii");
        assert!(!parsed_legacy.dim);
        assert_eq!(parsed_legacy.selected_level, "leve");
        assert!(parsed_legacy.custom_tweaks.is_none());

        let custom = Prefs {
            background: "nebulosa".into(),
            dim: true,
            selected_level: "equilibrado".into(),
            custom_tweaks: Some(vec!["copilot-off".into(), "win32-priority".into()]),
        };
        let encoded = custom.to_json_string();
        let decoded = Prefs::from_json_str(&encoded);
        assert_eq!(decoded.background, "nebulosa");
        assert_eq!(decoded.selected_level, "equilibrado");
        assert_eq!(decoded.custom_tweaks, Some(vec!["copilot-off".into(), "win32-priority".into()]));
    }

    #[test]
    fn backgrounds_only_include_the_three_finalists() {
        assert_eq!(BACKGROUNDS.len(), 3);
        let keys: Vec<&str> = BACKGROUNDS.iter().map(|(k, _, _)| *k).collect();
        assert_eq!(keys, vec!["eclipse", "nebulosa", "torii"]);
    }

    #[test]
    fn manual_page_ids_match_real_public_tweaks() {
        let public_tweaks = Edicao::Publica.tweaks();
        let public_ids: HashSet<&str> = public_tweaks.iter().map(|t| t.id.as_str()).collect();
        for id in POWER_IDS.iter().chain(APPS_IDS).chain(SERVICES_IDS) {
            assert!(public_ids.contains(id), "tweak id {id} must exist in public catalog");
        }
    }

    #[test]
    fn level_plan_with_ambiente_skips_pro_and_build_only_items_when_absent() {
        let tweaks = Edicao::Publica.tweaks();
        let det = Deteccao { ssd: true, nvidia: true, bateria: false, gerenciado: false };
        let amb_home_old = Ambiente { pro: false, build: 22631 };
        let mut store = EmptyStore;
        let plan = plano_nivel_em(Nivel::Leve, &tweaks, &det, &amb_home_old, &mut store);
        assert!(plan.pulados.iter().any(|(id, _)| id == "lockscreen-tips-off"));
        assert!(plan.pulados.iter().any(|(id, _)| id == "clicktodo-off"));
        let mut selection = plan.selecao();
        assert!(!personalizado(&selection, &plan));
        selection.insert("win32-priority");
        assert!(personalizado(&selection, &plan));
    }

    #[test]
    fn cpu_100_option_exposes_heat_and_battery_warning_and_store_is_protected() {
        let warn = OpcaoEnergia::CpuMinima100.aviso().to_ascii_lowercase();
        assert!(warn.contains("calor") && warn.contains("bateria"));
        assert!(apps::APPS.iter().all(|a| a.chave != "store"));
        assert!(PROTEGIDOS.iter().any(|(pkg, _)| *pkg == "Microsoft.WindowsStore"));
    }

    #[test]
    fn avancado_protegido_blocks_powerdevice_and_tpm_by_name() {
        let power_dev = Dispositivo {
            instance_id: r"VMBUS\POWERDEVICE\0".into(),
            nome: "Hyper-V Power".into(),
            classe: "Other".into(),
            ativo: true,
        };
        let tpm_by_name = Dispositivo {
            instance_id: r"ACPI\MSFT0101\1".into(),
            nome: "Trusted Platform Module 2.0".into(),
            classe: "Other".into(),
            ativo: true,
        };
        assert!(avancado::protegido(&power_dev));
        assert!(avancado::protegido(&tpm_by_name));
    }

    #[test]
    fn aplicar_ajuste_and_estado_checado_surface_eligibility_and_denied_errors() {
        use vanta_core::tweaks::TweakError;

        struct DeniedStore;
        impl SystemStore for DeniedStore {
            fn get_value(&self, _: &str, _: &str) -> Option<RegValue> { None }
            fn set_value(&mut self, _: &str, _: &str, _: &str, _: RegValue) {}
            fn delete_value(&mut self, _: &str, _: &str) {}
            fn get_service_start(&self, _: &str) -> Option<String> { None }
            fn set_service_start(&mut self, _: &str, _: &str) {}
            fn service_lookup(&self, _: &str) -> ServiceLookup {
                ServiceLookup::Denied("ERROR_ACCESS_DENIED".into())
            }
        }

        let tweaks = Edicao::Publica.tweaks();
        let clicktodo = tweaks.iter().find(|t| t.id == "clicktodo-off").expect("clicktodo-off");
        let det = Deteccao { ssd: true, nvidia: false, bateria: false, gerenciado: false };
        let amb_home = Ambiente { pro: false, build: 26300 };
        let mut store = EmptyStore;
        let res = vanta_core::niveis::aplicar_ajuste(&mut store, clicktodo, true, &det, &amb_home);
        assert!(matches!(res, Err(TweakError::NotEligible(_))));

        let denied = DeniedStore;
        let svc_res = servicos::estado_checado(&denied, "MapsBroker", StartType::Manual);
        assert!(svc_res.is_err());
    }

    #[test]
    fn page_notice_is_isolated_by_page_and_settings_area() {
        use super::super::app::PageNotice;

        let opt_notice = PageNotice {
            page: Page::Optimize,
            area: None,
            kind: NoticeKind::Error,
            message: "Erro ao aplicar Competitivo".into(),
        };
        assert!(opt_notice.matches(Page::Optimize, "Geral"));
        assert!(!opt_notice.matches(Page::Power, "Geral"));
        assert!(!opt_notice.matches(Page::Services, "Geral"));
        assert!(!opt_notice.matches(Page::Settings, "Geral"));

        let settings_notice = PageNotice {
            page: Page::Settings,
            area: Some("Jogos".into()),
            kind: NoticeKind::Error,
            message: "Precisa de administrador".into(),
        };
        assert!(settings_notice.matches(Page::Settings, "Jogos"));
        assert!(!settings_notice.matches(Page::Settings, "Geral"));
        assert!(!settings_notice.matches(Page::Power, "Jogos"));

        let info_notice = PageNotice {
            page: Page::Services,
            area: None,
            kind: NoticeKind::Info,
            message: "Serviço ausente neste Windows (pulado): Fax.".into(),
        };
        assert_eq!(info_notice.kind, NoticeKind::Info);
        assert!(info_notice.matches(Page::Services, "Geral"));
        assert!(!info_notice.matches(Page::Power, "Geral"));
        assert!(!info_notice.matches(Page::Optimize, "Geral"));
    }

    #[test]
    fn banner_colors_meet_wcag_aa_contrast() {
        fn channel(byte: u8) -> f64 {
            let s = f64::from(byte) / 255.0;
            if s <= 0.03928 { s / 12.92 } else { ((s + 0.055) / 1.055).powf(2.4) }
        }
        fn luminance(rgb: u32) -> f64 {
            let r = ((rgb >> 16) & 0xFF) as u8;
            let g = ((rgb >> 8) & 0xFF) as u8;
            let b = (rgb & 0xFF) as u8;
            0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
        fn contrast(fg: u32, bg: u32) -> f64 {
            let (l1, l2) = (luminance(fg), luminance(bg));
            let (hi, lo) = if l1 >= l2 { (l1, l2) } else { (l2, l1) };
            (hi + 0.05) / (lo + 0.05)
        }

        // Alert boxes & Energia inline warnings (fg vs dark tinted surface bg)
        let pairs = [
            ("INK on ERR banner", INK, 0x211319),
            ("ERR on ERR banner", ERR, 0x211319),
            ("INK on WARN banner", INK, 0x211B11),
            ("WARN on CPU100 warning", WARN, 0x241D11),
            ("INK_MUTED on secondary power warning", INK_MUTED, 0x1B1715),
            ("INK on OK banner", INK, 0x111F18),
            ("OK on OK banner", OK, 0x111F18),
            ("INK on INFO banner", INK, 0x1A1628),
            ("ACCENT_TEXT on INFO banner", ACCENT_TEXT, 0x1A1628),
        ];
        for (name, fg, bg) in pairs {
            let ratio = contrast(fg, bg);
            assert!(ratio >= 4.5, "{name} contrast {ratio:.2}:1 must be >= 4.5:1 (WCAG AA)");
        }
    }
}
