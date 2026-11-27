//! Step 2, Your choices: one screen of the Atlas package's choices at a time.
//! Updating or reinstalling an installed Atlas first asks whether to keep the
//! choices this PC has or to choose again.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::rc::Rc;

use gpui::{
    AnyElement, Context, FontWeight, IntoElement, KeyDownEvent, ParentElement, Role, Styled, div, prelude::*,
    px,
};

use super::InstallPage;
use super::summary::{choice_value, chosen_on};
use crate::i18n::describe;
use crate::model::{AppModel, FixedChoice, ScreenKind, UpdatePath};
use crate::pages::{ListEntry, OptionNote, card_body, detail_row, option_page_card_with, step_card_header};
use crate::services::atlas_state::InstallIdentity;
use crate::services::package::ChoiceKind;
use crate::t;
use crate::theme::ActiveTheme;
use crate::ui::{
    Button, CheckBox, Icon, InfoBar, RadioGroup, RadioItem, Severity, Typography, a11y_text, card,
    focus_ring, icon_sized,
};

/// Modo de seleção exibido no topo da tela de escolhas (estado apenas visual).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) enum ChoiceMode {
    #[default]
    Manual,
    Recommended,
}

/// Conjunto do modo "Recomendado pelo Vanta" num único lugar de dados, fácil de ajustar.
///
/// - `single`: escolhas únicas (radio) aplicadas em todas as telas da Etapa 2:
///   Defender ligado, mitigações mantidas, atualizações manuais após instalar, teclado em layout único e Brave.
/// - `multiple_excluded`: caixas opcionais (`ChoiceKind::Multiple`) mantidas DESLIGADAS no Recomendado;
///   todas as demais caixas múltiplas do manifesto ficam LIGADAS.
///   - `disable-core-isolation`: VBS permanece ligado.
///   - `disable-phishing-protection`: Proteção contra Phishing permanece ligada.
///   - `remove-store`: mantém Microsoft Store (Game Pass / amigos).
///   - `remove-snipping-tool`: mantém Ferramenta de Captura.
struct RecommendedPreset {
    single: &'static [(&'static str, &'static str)],
    multiple_excluded: &'static [&'static str],
}

const RECOMMENDED_PRESET: RecommendedPreset = RecommendedPreset {
    single: &[
        ("defender", "defender-enable"),
        ("mitigations", "mitigations-default"),
        ("auto-updates", "auto-updates-disable"),
        ("keyboard", "keyboard-single"),
        ("browser", "browser-brave"),
    ],
    multiple_excluded: &[
        "disable-core-isolation",
        "disable-phishing-protection",
        "remove-store",
        "remove-snipping-tool",
        "install-eclean",
        // Opening Vanta Tools by itself after the restart only raises its administrator prompt out of the blue.
        "tools-on-logon",
    ],
};

/// Opção de Isolamento de Núcleo protegida pela confirmação do Valorant (F3).
const CORE_ISOLATION_OPTION: &str = "disable-core-isolation";

/// Retorna se `option_id` é a opção recomendada de `choice_id`, calculada a partir
/// da fonte única [`RECOMMENDED_PRESET`].
fn is_recommended_single(choice_id: &str, option_id: &str) -> bool {
    RECOMMENDED_PRESET.single.iter().any(|&(c, opt)| c == choice_id && opt == option_id)
}

/// O seletor Recomendado/Manual aparece SOMENTE na Escolha 5 (opções extras),
/// nunca nas telas 1 a 4 (escolhas obrigatórias de 2–3 itens).
fn shows_choice_mode(required: bool, kind: ScreenKind, may_edit: bool) -> bool {
    may_edit && !required && kind != ScreenKind::UpdatePath
}

/// Verifica se `model.options` ainda está idêntico aos padrões virgens do manifesto
/// (nenhuma escolha customizada nem rascunho alterado pelo usuário).
fn options_match_manifest_defaults(model: &AppModel) -> bool {
    let defaults: BTreeSet<String> = model.manifest().default_options().into_iter().collect();
    model.options == defaults
}

/// Ao abrir uma tela obrigatória (1 a 4) pela primeira vez numa instalação nova sem rascunho prévio,
/// garante que a opção recomendada de [`RECOMMENDED_PRESET`] já venha selecionada — sem nunca
/// sobrescrever uma escolha anterior salva no rascunho.
fn seed_recommended_single(
    model: &mut AppModel,
    page_index: usize,
    allow_replace_manifest_default: bool,
    cx: &mut Context<AppModel>,
) {
    let Some(choice) = model.manifest().choices.get(page_index).cloned() else { return };
    if choice.kind != ChoiceKind::Single {
        return;
    }
    let Some(&(_, target)) = RECOMMENDED_PRESET.single.iter().find(|&&(id, _)| id == choice.id) else {
        return;
    };
    if !choice.options.iter().any(|o| o.id == target) || model.options.contains(target) {
        return;
    }
    let current = choice.options.iter().find(|o| model.options.contains(&o.id));
    match current {
        // Nenhuma opção escolhida ainda neste grupo: aplica o recomendado.
        None => model.choose_option(page_index, target, cx),
        // Só troca o default técnico do manifesto (ex.: keyboard-shortcuts -> keyboard-single)
        // num fluxo novo virgem vindo da Etapa 1; nunca sobrescreve escolha salva em rascunho.
        Some(opt) if allow_replace_manifest_default && opt.default => {
            model.choose_option(page_index, target, cx);
        }
        Some(_) => {}
    }
}

/// Coleta todas as telas obrigatórias (1 a 4) ainda não semeadas para inicializar
/// seus padrões recomendados em lote na primeira entrada na etapa de Opções.
fn pending_required_seeds(
    state: &AppModel,
    seen_ready_step: bool,
    seeded: &HashSet<String>,
) -> Option<(Vec<(String, usize)>, bool)> {
    let may_edit = !state.locked() && state.locked_options().is_none();
    let is_fresh = matches!(state.install_identity, Ok(InstallIdentity::Fresh));
    if !may_edit || !is_fresh {
        return None;
    }
    let allow_replace_manifest_default =
        seen_ready_step && !state.returning_to_install && options_match_manifest_defaults(state);
    let pending: Vec<(String, usize)> = state
        .option_screens()
        .into_iter()
        .filter(|screen| screen.required)
        .filter_map(|screen| {
            let &page_index = screen.pages.first()?;
            let choice = state.manifest().choices.get(page_index)?;
            if seeded.contains(&choice.id) {
                return None;
            }
            Some((choice.id.clone(), page_index))
        })
        .collect();
    (!pending.is_empty()).then_some((pending, allow_replace_manifest_default))
}

/// Semeia em lote os padrões recomendados de todas as telas obrigatórias pendentes (1 a 4).
/// Em fluxo novo virgem vindo da Etapa 1, aplica os padrões antes de qualquer edição
/// (garantindo `keyboard-single` na Tela 4 mesmo se o usuário editar as telas 1–3 antes de visitá-la).
/// Em rascunho reaberto ou já editado, preserva todas as escolhas salvas e preenche apenas grupos vazios.
fn seed_required_recommended_singles(
    model: &mut AppModel,
    seeded: &mut HashSet<String>,
    seen_ready_step: bool,
    cx: &mut Context<AppModel>,
) {
    let Some((pending, allow_replace_manifest_default)) =
        pending_required_seeds(model, seen_ready_step, seeded)
    else {
        return;
    };
    for (choice_id, page_index) in pending {
        seeded.insert(choice_id);
        seed_recommended_single(model, page_index, allow_replace_manifest_default, cx);
    }
}

/// Aplica [`RECOMMENDED_PRESET`] SOMENTE nas páginas da Escolha 5 (`pages`),
/// preservando intacto tudo o que o usuário escolheu nas telas 1 a 4 e o contrato de `state.json`.
fn apply_recommended_on_pages(model: &mut AppModel, pages: &[usize], cx: &mut Context<AppModel>) {
    let choices = model.manifest().choices.clone();
    // Primeiro as escolhas múltiplas para garantir dependências (ex.: `install-another-browser` antes de `browser`).
    for &page_index in pages {
        let Some(choice) = choices.get(page_index) else { continue };
        if choice.kind == ChoiceKind::Multiple {
            for option in &choice.options {
                let want_on = !RECOMMENDED_PRESET.multiple_excluded.contains(&option.id.as_str());
                let is_on = model.options.contains(&option.id);
                if want_on != is_on {
                    model.choose_option(page_index, &option.id, cx);
                }
            }
        }
    }
    for &page_index in pages {
        let Some(choice) = choices.get(page_index) else { continue };
        if choice.kind == ChoiceKind::Single
            && let Some(&(_, target)) = RECOMMENDED_PRESET.single.iter().find(|&&(id, _)| id == choice.id)
            && choice.options.iter().any(|o| o.id == target)
            && !model.options.contains(target)
        {
            model.choose_option(page_index, target, cx);
        }
    }
}

/// Desmarca todas as caixas opcionais (`ChoiceKind::Multiple`) da Escolha 5 (`pages`)
/// para escolha manual limpa, preservando opções fixas e escolhas das telas 1 a 4.
fn clear_optional_choices_on_pages(model: &mut AppModel, pages: &[usize], cx: &mut Context<AppModel>) {
    let choices = model.manifest().choices.clone();
    for &page_index in pages {
        let Some(choice) = choices.get(page_index) else { continue };
        if choice.kind == ChoiceKind::Multiple {
            for option in &choice.options {
                if model.options.contains(&option.id) {
                    model.choose_option(page_index, &option.id, cx);
                }
            }
        }
    }
}

/// Explicação da opção na Escolha 5 (o que faz, ganho, cuidado) no mesmo formato direto
/// do Vanta Tools: reutiliza `consequence-*` quando existe e combina com `option-why-<id>`.
fn option_why(id: &str) -> Option<String> {
    Some(match id {
        "disable-hibernation" => t!("option-why-disable-hibernation"),
        "disable-power-saving" => t!("option-why-disable-power-saving"),
        "disable-core-isolation" => t!("option-why-disable-core-isolation"),
        "disable-phishing-protection" => t!("option-why-disable-phishing-protection"),
        "disable-gamebar" => t!("option-why-disable-gamebar"),
        "remove-store" => t!("option-why-remove-store"),
        "vanta-power" => t!("option-why-vanta-power"),
        "vanta-memory" => t!("option-why-vanta-memory"),
        "tools-on-logon" => t!("option-why-tools-on-logon"),
        "remove-snipping-tool" => t!("option-why-remove-snipping-tool"),
        "uninstall-edge" => t!("option-why-uninstall-edge"),
        "install-another-browser" => t!("option-why-install-another-browser"),
        "install-eclean" => t!("option-why-install-eclean"),
        "browser-brave" => t!("option-why-browser-brave"),
        "browser-librewolf" => t!("option-why-browser-librewolf"),
        "browser-firefox" => t!("option-why-browser-firefox"),
        "browser-chrome" => t!("option-why-browser-chrome"),
        _ => return None,
    })
}

/// Dica completa exibida no hover do mouse e no foco pelo teclado nas opções da Escolha 5.
fn option_tooltip(id: &str, before_desktop: bool) -> Option<String> {
    let why = option_why(id);
    let consequence = describe::install_consequence(id, before_desktop);
    match (consequence, why) {
        (Some(cons), Some(why)) => Some(format!("{cons}
{why}")),
        (Some(cons), None) => Some(cons),
        (None, Some(why)) => Some(why),
        (None, None) => None,
    }
}

/// Alterna a trava do Isolamento de Núcleo (F3): desmarcar a caixa volta `disable-core-isolation`
/// para desmarcado (isolamento ligado).
fn set_core_isolation_unlocked(
    unlocked: &mut bool,
    value: bool,
    page_index: usize,
    model: &mut AppModel,
    cx: &mut Context<AppModel>,
) {
    *unlocked = value;
    if !value && model.options.contains(CORE_ISOLATION_OPTION) {
        model.choose_option(page_index, CORE_ISOLATION_OPTION, cx);
    }
}

impl InstallPage {
    pub(super) fn options_cards(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        // Sincroniza uma única vez a trava do Isolamento de Núcleo caso o rascunho já tenha a opção marcada,
        // e semeia em lote a pré-seleção recomendada nas telas 1 a 4 ao entrar em Opções num fluxo novo
        // (antes de qualquer edição nas telas 1–3), sem sobrescrever escolhas salvas em rascunho.
        let needs_seed = {
            let state = self.model.read(cx);
            if !self.core_isolation_synced || state.options.contains(CORE_ISOLATION_OPTION) {
                if state.options.contains(CORE_ISOLATION_OPTION) {
                    self.core_isolation_unlocked = true;
                }
                self.core_isolation_synced = true;
            }
            pending_required_seeds(state, self.seen_ready_step, &self.seeded_recommended_singles).is_some()
        };
        if needs_seed {
            let seen_ready_step = self.seen_ready_step;
            let seeded = &mut self.seeded_recommended_singles;
            self.model
                .update(cx, |m, cx| seed_required_recommended_singles(m, seeded, seen_ready_step, cx));
        }

        let theme = cx.theme().clone();
        let unlocked = self.core_isolation_unlocked;
        let (manifest, options, may_edit, screens, current, package_dir, notes) = {
            let state = self.model.read(cx);
            let screens = state.option_screens();
            let current = state.current_option_screen();
            let notes = screens
                .get(current)
                .map(|screen| option_notes(state, &screen.pages, screen.required, unlocked))
                .unwrap_or_default();
            (
                state.manifest().clone(),
                state.effective_options().into_iter().collect::<BTreeSet<_>>(),
                !state.locked() && state.locked_options().is_none(),
                screens,
                current,
                state.package.as_ref().map(|package| package.dir.clone()),
                notes,
            )
        };
        let Some(screen) = screens.get(current) else { return Vec::new() };
        if screen.kind == ScreenKind::UpdatePath {
            return self.update_path_cards(cx);
        }
        let model = self.model.clone();
        let page_entity = cx.entity();
        let mut cards: Vec<AnyElement> =
            choices_bar(self.model.read(cx)).into_iter().map(IntoElement::into_any_element).collect();

        // One decision at a time: the question is the heading, the choice
        // below it, with consequences visible before either answer is chosen.
        // Beside where the user is, which choices can be changed afterwards.
        let kinds: Vec<ScreenKind> = screens.iter().map(|screen| screen.kind).collect();
        let (number, total) = choice_progress(&kinds, current).unwrap_or((current + 1, screens.len()));
        cards.push(
            div()
                .flex()
                .flex_wrap()
                .items_start()
                .gap_x(px(16.))
                .gap_y(px(2.))
                .type_caption()
                .text_color(theme.text_secondary)
                .child(div().flex_shrink_0().child(a11y_text(
                    "option-progress",
                    if screen.required {
                        t!("options-progress", number = number, total = total)
                    } else {
                        t!("options-progress-extras", number = number, total = total)
                    },
                )))
                .child(change_later())
                .into_any_element(),
        );

        if shows_choice_mode(screen.required, screen.kind, may_edit) {
            cards.push(self.choice_mode_card(cx));
        }

        for &page_index in &screen.pages {
            let page = &manifest.choices[page_index];
            if page.depends_on.as_ref().is_some_and(|dependency| !options.contains(dependency)) {
                continue;
            }
            let header =
                if screen.required { screen.kind.question() } else { ScreenKind::of_choice(page).title() };
            let model_for_choose = model.clone();
            let page_for_choose = page_entity.clone();
            let model_for_unlock = model.clone();
            let page_for_unlock = page_entity.clone();
            let chosen = options.clone();
            let notes_ref = &notes;
            cards.push(option_page_card_with(
                cx,
                "option",
                page_index,
                page,
                header,
                move |name| chosen.contains(name),
                !may_edit,
                &mut self.focus,
                |option| notes_ref.get(&option.id).cloned().unwrap_or_default(),
                Rc::new(move |name: &str, cx: &mut gpui::App| {
                    let name = name.to_owned();
                    page_for_choose.update(cx, |this, cx| {
                        if this.choice_mode != ChoiceMode::Manual {
                            this.choice_mode = ChoiceMode::Manual;
                            cx.notify();
                        }
                    });
                    model_for_choose.update(cx, |m, cx| m.choose_option(page_index, &name, cx))
                }),
                package_dir.as_deref(),
                |option, _cx| {
                    if option.id != CORE_ISOLATION_OPTION {
                        return None;
                    }
                    let fixed = notes_ref.get(CORE_ISOLATION_OPTION).is_some_and(|n| n.fixed.is_some());
                    let model_toggle = model_for_unlock.clone();
                    let page_toggle = page_for_unlock.clone();
                    Some(
                        div()
                            .pl(px(28.))
                            .pb(px(4.))
                            .child(
                                CheckBox::new(
                                    "option-core-isolation-unlock",
                                    t!("option-core-isolation-unlock"),
                                    unlocked,
                                )
                                .disabled(!may_edit || fixed)
                                .on_toggle(move |_, _, cx| {
                                    let next = !unlocked;
                                    let mut flag = unlocked;
                                    model_toggle.update(cx, |m, cx| {
                                        set_core_isolation_unlocked(&mut flag, next, page_index, m, cx);
                                    });
                                    page_toggle.update(cx, |this, cx| {
                                        this.core_isolation_unlocked = flag;
                                        if !flag && this.choice_mode != ChoiceMode::Manual {
                                            this.choice_mode = ChoiceMode::Manual;
                                        }
                                        cx.notify();
                                    });
                                }),
                            )
                            .into_any_element(),
                    )
                },
            ));
        }
        cards
    }

    /// Cartão no topo da tela de escolhas com os dois modos: Recomendado e Escolher manualmente.
    fn choice_mode_card(&mut self, cx: &mut Context<Self>) -> AnyElement {
        let theme = cx.theme().clone();
        let mode = self.choice_mode;
        let recommended_active = mode == ChoiceMode::Recommended;
        let manual_active = mode == ChoiceMode::Manual;
        let detail = if recommended_active {
            t!("options-mode-recommended-detail")
        } else {
            t!("options-mode-manual-detail")
        };
        let seg_style = |id: &'static str, label: String, active: bool, theme: &crate::theme::Theme| {
            let border = if active {
                if theme.high_contrast { theme.accent } else { theme.accent_soft_stroke }
            } else {
                gpui::transparent_black()
            };
            let bg = if active {
                if theme.high_contrast { theme.control_fill } else { theme.accent_soft }
            } else {
                gpui::transparent_black()
            };
            let fg = if active { theme.text_primary } else { theme.text_secondary };
            let hover_bg = if active { bg } else { theme.subtle_hover };
            let hover_fg = theme.text_primary;
            let pressed_bg = theme.subtle_pressed;
            let focus_outer = theme.focus_outer;
            let focus_inner = theme.focus_inner;
            let check_color = theme.accent_text;
            div()
                .id(id)
                .role(Role::RadioButton)
                .aria_label(label.clone())
                .aria_selected(active)
                .tab_index(0)
                .cursor_pointer()
                .flex()
                .items_center()
                .gap(px(6.))
                .px(px(12.))
                .py(px(6.))
                .rounded(px(6.))
                .border_1()
                .border_color(border)
                .bg(bg)
                .text_color(fg)
                .type_body()
                .when(active, |d| d.font_weight(FontWeight::SEMIBOLD))
                .hover(move |s| s.bg(hover_bg).text_color(hover_fg))
                .active(move |s| s.bg(pressed_bg))
                .focus_visible(move |s| focus_ring(s, focus_outer, focus_inner))
                .when(active, |d| d.child(icon_sized(Icon::CheckMark, 12.).text_color(check_color)))
                .child(label)
        };

        let recommended_btn =
            seg_style("options-mode-recommended", t!("options-mode-recommended"), recommended_active, &theme)
                .on_click(cx.listener(|this, _, _, cx| {
                    this.select_recommended_mode(cx);
                }))
                .on_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
                    if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                        this.select_recommended_mode(cx);
                    }
                }));

        let manual_btn = seg_style("options-mode-manual", t!("options-mode-manual"), manual_active, &theme)
            .on_click(cx.listener(|this, _, _, cx| {
                this.select_manual_mode(cx);
            }))
            .on_key_down(cx.listener(|this, event: &KeyDownEvent, _, cx| {
                if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                    this.select_manual_mode(cx);
                }
            }));

        let segmented = div()
            .id("options-mode-group")
            .role(Role::RadioGroup)
            .aria_label(t!("options-mode-title"))
            .flex()
            .flex_wrap()
            .items_center()
            .gap(px(4.))
            .p(px(3.))
            .rounded(px(8.))
            .bg(theme.layer_fill)
            .border_1()
            .border_color(theme.card_stroke)
            .child(recommended_btn)
            .child(manual_btn);

        let proceed = recommended_active.then(|| {
            div()
                .flex()
                .items_center()
                .justify_end()
                .px(px(16.))
                .py(px(10.))
                .border_t_1()
                .border_color(theme.divider)
                .child(
                    Button::new("options-mode-proceed", t!("options-mode-proceed"))
                        .accent()
                        .trailing_icon(Icon::ChevronRight)
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.proceed_with_recommended(cx);
                        })),
                )
        });

        card(cx)
            .child(
                div()
                    .flex()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap(px(12.))
                    .px(px(16.))
                    .py(px(14.))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .flex_1()
                            .min_w(px(240.))
                            .child(
                                div()
                                    .type_body_strong()
                                    .text_color(theme.text_primary)
                                    .child(a11y_text("options-mode-title", t!("options-mode-title"))),
                            )
                            .child(
                                div()
                                    .type_caption()
                                    .text_color(theme.text_secondary)
                                    .child(a11y_text("options-mode-detail", detail)),
                            ),
                    )
                    .child(segmented),
            )
            .children(proceed)
            .into_any_element()
    }

    fn current_screen_pages(&self, cx: &gpui::App) -> Vec<usize> {
        let state = self.model.read(cx);
        let screens = state.option_screens();
        screens.get(state.current_option_screen()).map(|s| s.pages.clone()).unwrap_or_default()
    }

    fn select_recommended_mode(&mut self, cx: &mut Context<Self>) {
        let pages = self.current_screen_pages(cx);
        self.model.update(cx, |m, cx| apply_recommended_on_pages(m, &pages, cx));
        self.choice_mode = ChoiceMode::Recommended;
        cx.notify();
    }

    fn select_manual_mode(&mut self, cx: &mut Context<Self>) {
        let pages = self.current_screen_pages(cx);
        self.model.update(cx, |m, cx| clear_optional_choices_on_pages(m, &pages, cx));
        self.choice_mode = ChoiceMode::Manual;
        cx.notify();
    }

    fn proceed_with_recommended(&mut self, cx: &mut Context<Self>) {
        let pages = self.current_screen_pages(cx);
        self.model.update(cx, |m, cx| {
            apply_recommended_on_pages(m, &pages, cx);
            let last = m.option_screens().len().saturating_sub(1);
            m.option_screen = last;
            m.next_step(cx);
        });
    }

    /// The first screen of an update or reinstall: keep the choices this PC
    /// has, or choose again, above what the PC has now, choice by choice, as
    /// the summary lists them. Choosing again starts every screen from that
    /// list too. The answer can be changed while the choices it keeps can't.
    fn update_path_cards(&mut self, cx: &mut Context<Self>) -> Vec<AnyElement> {
        let focus = [self.focus.get("update-path-keep", cx), self.focus.get("update-path-choose", cx)];
        let model = self.model.clone();
        let state = self.model.read(cx);
        let (Some(update), Some(question)) = (state.update_choices(), update_path_question(state)) else {
            return Vec::new();
        };
        let theme = cx.theme();
        let [keep, choose] = focus;
        let paths = [UpdatePath::Keep, UpdatePath::ChooseAgain];
        let group = RadioGroup::new("update-path", question.clone())
            .items([
                RadioItem::new("update-path-keep", t!("update-path-keep"), keep)
                    .description(t!("update-path-keep-detail")),
                RadioItem::new("update-path-choose", t!("update-path-choose"), choose)
                    .description(t!("update-path-choose-detail")),
            ])
            .selected(paths.iter().position(|path| *path == state.update_path))
            .disabled(state.locked())
            .on_select({
                let page_entity = cx.entity();
                move |index, _, cx| {
                    if let Some(&path) = paths.get(index) {
                        page_entity.update(cx, |this, _| this.choice_mode = ChoiceMode::Manual);
                        model.update(cx, |m, cx| m.set_update_path(path, cx));
                    }
                }
            });

        let mut now = card_body();
        if let Some(line) = differs_line(&update.differs) {
            now = now.child(
                div()
                    .type_body()
                    .text_color(theme.text_secondary)
                    .pb(px(4.))
                    .child(a11y_text("update-path-differs", line)),
            );
        }
        for (index, row) in now_rows(state, &update.kept).into_iter().enumerate() {
            let chosen = row
                .chosen
                .iter()
                .filter_map(|name| Some(ListEntry::option(name, state.option_text(name)?)))
                .collect();
            let title = row.kind.title();
            let key = format!("now-{index}");
            let unknown = t!("update-path-unknown");
            let value = choice_value(cx, &key, ("now-choices", index), &title, row.required, chosen, unknown);
            now = now.child(detail_row(cx, &key, title, value));
        }
        vec![
            // No "Choice 1 of N": this asks how to treat the choices, not one of them.
            div()
                .flex()
                .type_caption()
                .text_color(theme.text_secondary)
                .child(change_later())
                .into_any_element(),
            card(cx)
                .child(step_card_header(cx, "update-path", question, None))
                .child(card_body().child(group))
                .into_any_element(),
            card(cx)
                .child(step_card_header(cx, "update-path-now", t!("update-path-now-title"), None))
                .child(now)
                .into_any_element(),
        ]
    }
}

/// Which choices can be changed afterwards, beside where the user is.
fn change_later() -> gpui::Div {
    div().flex_1().min_w(px(240.)).child(a11y_text("option-change-later", t!("options-change-later")))
}

/// A row of the first screen's list of what this PC has: a choice, as the
/// summary lists it, and the options the PC has for it, by name. A required
/// choice with none is one Atlas can't tell from the PC, which keeping the
/// choices then asks.
#[derive(Clone, Debug, PartialEq, Eq)]
struct NowRow {
    kind: ScreenKind,
    required: bool,
    chosen: Vec<String>,
}

/// The first screen's list, one row per choice in the summary's order, from
/// `kept`, the choices this PC has.
fn now_rows(state: &AppModel, kept: &[String]) -> Vec<NowRow> {
    let manifest = state.manifest();
    state
        .choice_screens()
        .into_iter()
        .map(|screen| NowRow {
            kind: screen.kind,
            required: screen.required,
            chosen: chosen_on(manifest, &screen.pages, kept, |option| option.id.clone()),
        })
        .collect()
}

/// The line above that list when Atlas's record of the last installation
/// doesn't match this PC, naming each choice of the kinds `differs`.
fn differs_line(differs: &[ScreenKind]) -> Option<String> {
    let choices: Vec<String> = differs.iter().map(|kind| kind.title()).collect();
    (!choices.is_empty()).then(|| t!("update-path-differs", choices = describe::join_and(&choices)))
}

/// The step heading's accessible name on a screen of Your choices, after
/// `heading`, the step: which choice and its question, or the optional
/// extras; on the first screen of an update or reinstall, what it asks.
pub(super) fn choice_heading_name(state: &AppModel, heading: &str) -> Option<String> {
    let screens = state.option_screens();
    let current = state.current_option_screen();
    let screen = screens.get(current)?;
    let kinds: Vec<_> = screens.iter().map(|screen| screen.kind).collect();
    let Some((number, total)) = choice_progress(&kinds, current) else {
        let question = update_path_question(state)?;
        return Some(t!("step-heading-update-path-a11y", heading = heading, question = question));
    };
    Some(if screen.required {
        t!(
            "step-heading-choice-a11y",
            heading = heading,
            progress = t!("options-progress", number = number, total = total),
            question = screen.kind.question()
        )
    } else {
        t!(
            "step-heading-extras-a11y",
            heading = heading,
            progress = t!("options-progress-extras", number = number, total = total)
        )
    })
}

/// The question the first screen of an update or reinstall asks, if this
/// flow has one: updating to the package's version, or installing again the
/// version this PC has.
fn update_path_question(state: &AppModel) -> Option<String> {
    let update = state.update_choices()?;
    let version = state.manifest().version.as_str();
    Some(if update.reinstall {
        t!("update-path-reinstall-title", version = version)
    } else {
        t!("update-path-update-title", version = version)
    })
}

/// Which choice of how many the screen at `current` is, given the kinds of
/// every screen: the first screen of an update or reinstall asks nothing of
/// the package, so it isn't counted, and has no number itself.
fn choice_progress(kinds: &[ScreenKind], current: usize) -> Option<(usize, usize)> {
    let asked = usize::from(kinds.first() == Some(&ScreenKind::UpdatePath));
    let kind = kinds.get(current)?;
    (*kind != ScreenKind::UpdatePath).then(|| (current + 1 - asked, kinds.len() - asked))
}

/// Which bar a screen of choices shows above it, and what it names.
#[derive(Clone, Debug, PartialEq, Eq)]
enum ChoicesNote {
    /// An unfinished install keeps the options it began with.
    Resume,
    /// Windows rebuilt itself: the choices the record of the move kept from
    /// Atlas `previous`, and the required ones it couldn't find, if any.
    Rebase { previous: String, missing: Vec<ScreenKind> },
    /// Keeping the choices of the installed Atlas asks only these, which
    /// this PC can't show.
    Keep(Vec<ScreenKind>),
    /// Choosing again starts each screen from how this PC is set up.
    ChooseAgain,
}

/// The note above a screen of choices: an unfinished install's, a rebuilt
/// Windows's, or how an update or reinstall treats them. An unfinished
/// update that will keep them, with nothing held yet, says so as keeping
/// them does while it asks a choice, and otherwise as an unfinished install.
/// A first install has none.
fn choices_note(state: &AppModel) -> Option<ChoicesNote> {
    if state.original_options().is_some() {
        return Some(ChoicesNote::Resume);
    }
    if let Some(choices) = state.rebase_choices() {
        return Some(ChoicesNote::Rebase { previous: choices.previous, missing: choices.missing });
    }
    if let Some(choices) = state.unfinished_choices() {
        return Some(if choices.complete() {
            ChoicesNote::Resume
        } else {
            ChoicesNote::Keep(choices.missing)
        });
    }
    let update = state.update_choices()?;
    Some(match state.update_path {
        UpdatePath::ChooseAgain => ChoicesNote::ChooseAgain,
        UpdatePath::Keep => ChoicesNote::Keep(update.missing),
    })
}

impl ChoicesNote {
    /// The bar's title, then its message. Keeping the choices names the
    /// screens it shows, which are what this PC can't show.
    fn words(&self) -> (String, String) {
        let titles = |kinds: &[ScreenKind]| {
            let titles: Vec<String> = kinds.iter().map(|kind| kind.title()).collect();
            describe::join_and(&titles)
        };
        match self {
            ChoicesNote::Resume => (t!("resume-choices-title"), t!("resume-choices-detail")),
            ChoicesNote::Rebase { previous, missing } => {
                let previous = previous.as_str();
                let detail = if missing.is_empty() {
                    t!("rebase-choices-detail", previous = previous)
                } else {
                    t!("rebase-choices-partial", previous = previous, missing = titles(missing).as_str())
                };
                (t!("rebase-choices-title", previous = previous), detail)
            }
            ChoicesNote::Keep(missing) => {
                (t!("keep-choices-title"), t!("keep-choices-partial", missing = titles(missing)))
            }
            ChoicesNote::ChooseAgain => (t!("choose-again-title"), t!("choose-again-detail")),
        }
    }
}

/// The bar [`choices_note`] decides, if any.
fn choices_bar(state: &AppModel) -> Option<InfoBar> {
    let note = choices_note(state)?;
    let (title, message) = note.words();
    let bar = InfoBar::new(Severity::Informational, title, message);
    Some(match note {
        ChoicesNote::Resume => bar,
        ChoicesNote::Rebase { .. } => bar.id("options-rebase-note"),
        ChoicesNote::Keep(_) => bar.id("options-keep-note"),
        ChoicesNote::ChooseAgain => bar.id("options-choose-again-note"),
    })
}

/// What each option on the pages `pages` says under it, by name. Every
/// option says what it means, removing Edge that it deletes its data on this
/// PC. Choosing again on an update or reinstall, an option also says what it
/// changes on this PC instead, whether the PC has it, and why an update
/// can't change it; a browser chosen beside one an update keeps installed
/// says both stay.
fn option_notes(
    state: &AppModel,
    pages: &[usize],
    required_screen: bool,
    core_isolation_unlocked: bool,
) -> HashMap<String, OptionNote> {
    let manifest = state.manifest();
    let options = state.effective_options();
    let chosen = |name: &str| options.iter().any(|option| option == name);
    let choosing_again = state.update_choices().filter(|_| state.update_path == UpdatePath::ChooseAgain);
    let facts = state.choice_facts();
    let inferred_off = state.inferred_off();
    let label = |id: &str| describe::option_label(id, state.option_text(id).unwrap_or(id));
    let kept_browser = match state.fixed_option("install-another-browser") {
        Some(FixedChoice::Installed(browser)) if choosing_again.is_some() => Some(browser),
        _ => None,
    };
    let mut notes = HashMap::new();
    for page in pages.iter().filter_map(|&index| manifest.choices.get(index)) {
        for option in &page.options {
            let name = option.id.as_str();
            let mut note = OptionNote::from(describe::install_consequence(name, state.before_desktop));
            if required_screen && page.kind == ChoiceKind::Single {
                note.recommended = is_recommended_single(&page.id, name);
            }
            if !required_screen {
                note.tooltip = option_tooltip(name, state.before_desktop);
            }
            if name == CORE_ISOLATION_OPTION && !core_isolation_unlocked {
                note.locked = true;
            }
            if inferred_off.iter().any(|option| option == name) {
                let notice = t!("option-detected-off");
                note.consequence = Some(match note.consequence.take() {
                    Some(consequence) => format!("{notice} {consequence}"),
                    None => notice,
                });
            }
            if let Some(update) = &choosing_again {
                let answered = page.kind == ChoiceKind::Single || chosen(name);
                note.change = describe::change_line(name, answered, &facts);
                note.now = update.kept.iter().any(|kept| kept == name);
                note.fixed = state.fixed_option(name).and_then(|fixed| describe::fixed_reason(&fixed, label));
                if let Some(installed) = kept_browser.as_deref()
                    && name.starts_with("browser-")
                    && name != installed
                    && chosen(name)
                {
                    note.change =
                        Some(t!("browser-also", installed = label(installed), browser = label(name)));
                }
            }
            notes.insert(option.id.clone(), note);
        }
    }
    notes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::test_harness::run_model_test;
    use crate::pages::testing::{NO_DEFENDER, NO_TELEMETRY, installed_model, rebuilt, records};
    use crate::services::atlas_state::{InstallIdentity, InstallMode, Unfinished};
    use crate::services::legacy_choices::Facts;
    use crate::services::test_support::TempDir;

    /// A PC whose record kept Microsoft Defender while Atlas's NoDefender
    /// package removes it, with every processor protection on, updates and
    /// hibernation off, Edge removed and a Toolbox and Brave installed.
    fn removed_pc() -> Facts {
        Facts {
            packages: vec![NO_DEFENDER.into(), NO_TELEMETRY.into()],
            toggles: records(&[("Mitigations", 2), ("AutomaticUpdates", 0), ("Hibernation", 0)]),
            edge: Some(false),
            appx: vec![
                "Microsoft.ScreenSketch_8wekyb3d8bbwe".into(),
                "Microsoft.WindowsCalculator_8wekyb3d8bbwe".into(),
            ],
            toolbox: Some(true),
            toolbox_program: Some(true),
            browser: Some("Brave".into()),
            browsers: Some(vec!["browser-brave".into()]),
            defender: Some(false),
            ..Facts::default()
        }
    }

    fn page_of(m: &AppModel, option: &str) -> usize {
        m.manifest().choices.iter().position(|page| page.options.iter().any(|o| o.id == option)).unwrap()
    }

    fn line(id: &str) -> Option<String> {
        Some(crate::i18n::text(id, &[]))
    }

    /// Choosing again on a PC its record contradicts, each answer that
    /// changes the PC says so, the PC's own answers are tagged, what an
    /// update can't undo is fixed with why, and a browser picked beside the
    /// one installed says both stay. Keeping the choices, or a first install,
    /// says only what each option means.
    #[test]
    fn choosing_again_says_what_each_answer_changes_on_this_pc() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("option-notes");
            let record =
                ["defender-enable", "mitigations-default", "auto-updates-disable", "keyboard-shortcuts"];
            let model = installed_model(&mut cx, &temp, Some(&record), removed_pc());
            let all = |m: &AppModel| (0..m.manifest().choices.len()).collect::<Vec<_>>();
            model.update(&mut cx, |m, cx| {
                m.update_path = UpdatePath::ChooseAgain;
                m.set_update_path(UpdatePath::Keep, cx);
                m.set_update_path(UpdatePath::ChooseAgain, cx);
                let notes = option_notes(m, &all(m), false, true);
                let note = |name: &str| notes[name].clone();
                assert_eq!(note("defender-enable").change, line("change-defender-enable"));
                assert!(!note("defender-enable").now);
                let removed = note("defender-disable");
                assert!(!removed.now && removed.change.is_none(), "found off, not chosen: not carried");
                assert_eq!(
                    removed.consequence,
                    Some(format!(
                        "{} {}",
                        t!("option-detected-off"),
                        line("consequence-defender-disable").unwrap()
                    )),
                    "says it was found off, then what it means"
                );
                let protections = note("mitigations-default");
                assert!(protections.now);
                assert_eq!(protections.change, line("change-mitigations-all-on"));
                assert_eq!(note("auto-updates-default").change, line("change-auto-updates-default"));
                assert!(note("auto-updates-disable").now && note("auto-updates-disable").change.is_none());
                assert_eq!(note("uninstall-edge").fixed, line("fixed-uninstall-edge"));
                assert_eq!(note("install-another-browser").fixed, Some(t!("fixed-installed", app = "Brave")));
                assert!(note("browser-brave").now && note("browser-brave").change.is_none());
                // Ticked as the PC has them: nothing changes until cleared.
                assert!(note("disable-hibernation").now && note("disable-hibernation").change.is_none());
                assert!(note("remove-snipping-tool").change.is_none() && !note("remove-snipping-tool").now);
                assert!(note("install-eclean").fixed.is_none() && note("install-eclean").change.is_none());

                m.choose_option(page_of(m, "disable-hibernation"), "disable-hibernation", cx);
                m.choose_option(page_of(m, "remove-snipping-tool"), "remove-snipping-tool", cx);
                m.choose_option(page_of(m, "browser-firefox"), "browser-firefox", cx);
                let notes = option_notes(m, &all(m), false, true);
                assert_eq!(notes["disable-hibernation"].change, line("change-hibernation-on"));
                assert_eq!(notes["remove-snipping-tool"].change, line("change-remove-snipping-tool"));
                assert_eq!(
                    notes["browser-firefox"].change,
                    Some(t!("browser-also", installed = "Brave", browser = "Firefox"))
                );
                assert!(notes["browser-brave"].change.is_none(), "only the browser chosen says it");

                // Keeping them, or a first install, only says what each means.
                m.set_update_path(UpdatePath::Keep, cx);
                for notes in [option_notes(m, &all(m), false, true), {
                    m.install_identity = Ok(InstallIdentity::Fresh);
                    option_notes(m, &all(m), false, true)
                }]
                .into_iter()
                .enumerate()
                {
                    let (index, notes) = notes;
                    for (name, note) in &notes {
                        assert!(
                            !note.now && note.change.is_none() && note.fixed.is_none(),
                            "{name}: {note:?}"
                        );
                    }
                    let meaning = line("consequence-defender-disable");
                    let found_off =
                        Some(format!("{} {}", t!("option-detected-off"), meaning.clone().unwrap()));
                    let expected = if index == 0 { found_off } else { meaning };
                    assert_eq!(notes["defender-disable"].consequence, expected, "notice only on an update");
                }
            });
        });
    }

    /// On a PC before 0.6, a Mitigations record without a launcher's name
    /// beside it is the old Toolbox's, which never changed the PC, so keeping
    /// processor protections says only what it means. The record Atlas 0.5's
    /// launcher left says every protection is on.
    #[test]
    fn choosing_again_reads_an_old_toolbox_s_record_for_what_it_means() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("option-notes-before-0-6");
            let pc = Facts {
                packages: vec![NO_TELEMETRY.into()],
                toggles: records(&[("Mitigations", 2)]),
                ..Facts::default()
            };
            let model = installed_model(&mut cx, &temp, None, pc);
            model.update(&mut cx, |m, cx| {
                m.install_identity = Ok(InstallIdentity::Installed("0.5.0".into()));
                m.set_update_path(UpdatePath::ChooseAgain, cx);
                let pages = [page_of(m, "mitigations-default")];
                assert_eq!(option_notes(m, &pages, true, false)["mitigations-default"].change, None);
                m.pc_facts.launchers =
                    [("Mitigations".to_owned(), "Enable All Mitigations.cmd".to_owned())].into();
                assert_eq!(
                    option_notes(m, &pages, true, false)["mitigations-default"].change,
                    line("change-mitigations-all-on")
                );
            });
        });
    }

    /// The first screen offers both answers, keeping them selected, and
    /// lists what this PC has: where Atlas's record says otherwise, then each
    /// choice as the PC has it, a required one it can't show as one Atlas
    /// asks. Its question names the version this flow installs, as an update
    /// or as a reinstall.
    #[test]
    fn the_first_screen_asks_how_to_update_or_reinstall() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("update-path-question");
            let model = installed_model(&mut cx, &temp, Some(&["defender-enable"]), removed_pc());
            model.update(&mut cx, |m, _| {
                assert_eq!(m.update_path, UpdatePath::Keep);
                let update = m.update_choices().unwrap();
                assert_eq!(
                    update.missing,
                    [ScreenKind::Defender, ScreenKind::Keyboard],
                    "nothing shows the keyboard choice, and Defender found off is asked, not carried"
                );
                let rows = now_rows(m, &update.kept);
                let kinds: Vec<ScreenKind> = rows.iter().map(|row| row.kind).collect();
                let screens: Vec<ScreenKind> = m.choice_screens().iter().map(|screen| screen.kind).collect();
                assert_eq!(kinds, screens, "the summary's rows");
                let unknown: Vec<ScreenKind> = rows
                    .iter()
                    .filter(|row| row.required && row.chosen.is_empty())
                    .map(|row| row.kind)
                    .collect();
                assert_eq!(unknown, update.missing, "read as update-path-unknown");
                assert!(rows[0].chosen.is_empty(), "Defender found off is asked, never carried");
                let extras = rows.last().unwrap();
                assert!(
                    !extras.required && extras.chosen.iter().any(|o| o == "uninstall-edge"),
                    "{extras:?}"
                );

                assert_eq!(update.differs.first(), Some(&ScreenKind::Defender));
                let titles: Vec<String> = update.differs.iter().map(|kind| kind.title()).collect();
                assert_eq!(
                    differs_line(&update.differs),
                    Some(t!("update-path-differs", choices = describe::join_and(&titles)))
                );
                assert_eq!(differs_line(&[]), None, "a record that matches says nothing");

                assert_eq!(
                    update_path_question(m),
                    Some(t!("update-path-reinstall-title", version = "0.6.0"))
                );
                m.install_identity = Ok(InstallIdentity::Installed("0.5.0".into()));
                assert_eq!(update_path_question(m), Some(t!("update-path-update-title", version = "0.6.0")));
                m.install_identity = Ok(InstallIdentity::Fresh);
                assert_eq!(update_path_question(m), None, "a first install has no first screen");
            });
        });
    }

    /// A screen after the first says how its choices are treated: keeping
    /// them names the ones this PC can't show, choosing again says each
    /// starts from the PC. An unfinished install and a rebuilt Windows have
    /// bars of their own, and a first install has none.
    #[test]
    fn the_bar_above_a_screen_says_how_its_choices_are_treated() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("choices-note");
            // No record of processor protections, so keeping the choices asks it.
            let pc = Facts {
                packages: vec![NO_TELEMETRY.into()],
                toggles: records(&[("AutomaticUpdates", 0), ("KeyboardShortcuts", 1)]),
                ..Facts::default()
            };
            let model = installed_model(&mut cx, &temp, Some(&["defender-enable"]), pc);
            model.update(&mut cx, |m, cx| {
                assert_eq!(choices_note(m), Some(ChoicesNote::Keep(vec![ScreenKind::Mitigations])));
                m.set_update_path(UpdatePath::ChooseAgain, cx);
                assert_eq!(choices_note(m), Some(ChoicesNote::ChooseAgain));
                let unfinished = Unfinished {
                    held: Some(vec!["defender-enable".into()]),
                    choose_again: true,
                    mode: InstallMode::Reapply,
                };
                m.install_identity = Ok(InstallIdentity::Resume("0.6.0".into(), unfinished));
                assert_eq!(choices_note(m), Some(ChoicesNote::Resume));
                // One that will keep them, with nothing held yet, asks as keeping them does.
                let unheld = Unfinished { held: None, choose_again: false, mode: InstallMode::Reapply };
                m.install_identity = Ok(InstallIdentity::Resume("0.6.0".into(), unheld));
                assert_eq!(choices_note(m), Some(ChoicesNote::Keep(vec![ScreenKind::Mitigations])));
                m.pc_facts.toggles.insert("Mitigations".into(), 1);
                assert_eq!(choices_note(m), Some(ChoicesNote::Resume), "nothing to ask");
                m.pc_facts.toggles.remove("Mitigations");
                m.install_identity = Ok(InstallIdentity::Installed("0.5.0".into()));
                m.atlas = Ok(None);
                m.update_access =
                    Some(rebuilt(&["defender-disable", "auto-updates-disable", "keyboard-shortcuts"]));
                assert_eq!(
                    choices_note(m),
                    Some(ChoicesNote::Rebase {
                        previous: "0.5.0".into(),
                        missing: vec![ScreenKind::Mitigations]
                    })
                );
                m.install_identity = Ok(InstallIdentity::Fresh);
                m.update_access = None;
                assert_eq!(choices_note(m), None, "a first install has none");
            });
        });
        crate::i18n::testing::english(|| {
            let missing = ChoicesNote::Keep(vec![ScreenKind::Mitigations, ScreenKind::Keyboard]).words();
            let titles = [ScreenKind::Mitigations.title(), ScreenKind::Keyboard.title()];
            let partial = t!("keep-choices-partial", missing = describe::join_and(&titles));
            assert!(partial.ends_with(&format!("{} and {}", titles[0], titles[1])), "{partial}");
            assert_eq!(missing, (t!("keep-choices-title"), partial));
            assert_eq!(
                ChoicesNote::ChooseAgain.words(),
                (t!("choose-again-title"), t!("choose-again-detail"))
            );
            let complete = ChoicesNote::Rebase { previous: "0.5.0".into(), missing: Vec::new() }.words();
            assert_eq!(complete.1, t!("rebase-choices-detail", previous = "0.5.0"));
            let partial =
                ChoicesNote::Rebase { previous: "0.5.0".into(), missing: vec![ScreenKind::Defender] };
            assert!(partial.words().1.ends_with(&ScreenKind::Defender.title()), "{:?}", partial.words());
        });
    }

    /// The step heading's accessible name says what the screen asks: the
    /// first screen its question, the next ones which choice they are, the
    /// first screen not counted.
    #[test]
    fn the_step_heading_names_what_the_screen_asks() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("choice-heading");
            let model = installed_model(&mut cx, &temp, Some(&["defender-enable"]), removed_pc());
            model.update(&mut cx, |m, cx| {
                let heading = "Step 2 of 4: Your choices";
                let question = t!("update-path-reinstall-title", version = "0.6.0");
                assert_eq!(
                    choice_heading_name(m, heading),
                    Some(t!("step-heading-update-path-a11y", heading = heading, question = question))
                );
                m.set_update_path(UpdatePath::ChooseAgain, cx);
                m.option_screen = 1;
                let progress = t!("options-progress", number = 1, total = 5);
                assert_eq!(
                    choice_heading_name(m, heading),
                    Some(t!(
                        "step-heading-choice-a11y",
                        heading = heading,
                        progress = progress,
                        question = ScreenKind::Defender.question()
                    ))
                );
            });
        });
    }

    #[test]
    fn the_first_screen_of_an_update_is_not_counted_among_the_choices() {
        use ScreenKind::{Defender, Extras, Mitigations, UpdatePath};
        let update = [UpdatePath, Defender, Mitigations, Extras];
        assert_eq!(choice_progress(&update, 0), None, "it asks nothing of the package");
        assert_eq!(choice_progress(&update, 1), Some((1, 3)));
        assert_eq!(choice_progress(&update, 3), Some((3, 3)));
        assert_eq!(choice_progress(&update, 4), None);
        let first_install = [Defender, Mitigations, Extras];
        assert_eq!(choice_progress(&first_install, 0), Some((1, 3)));
        assert_eq!(choice_progress(&first_install, 2), Some((3, 3)));
    }

    /// F2: Telas 1 a 4 nunca exibem `options-mode-group` (mostram apenas "(recomendado)"
    /// calculado a partir de `RECOMMENDED_PRESET.single` e vêm pré-selecionadas).
    /// A Tela 5 exibe o seletor e aplica o Recomendado SOMENTE nas opções dela,
    /// preservando tudo o que o usuário escolheu nas telas 1 a 4.
    /// Todas as opções da Tela 5 têm dica (tooltip) não vazia.
    #[test]
    fn recommended_selector_only_on_choice_5_and_preserves_earlier_screens() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("preset-choice-5");
            let model = installed_model(&mut cx, &temp, None, Facts::default());
            model.update(&mut cx, |m, _| {
                m.install_identity = Ok(InstallIdentity::Fresh);
                m.atlas = Ok(None);
                m.options.clear();
            });
            model.update(&mut cx, |m, cx| {
                let screens = m.option_screens();
                assert_eq!(screens.len(), 5, "4 telas obrigatórias + 1 tela de extras");

                // Telas 1 a 4: sem options-mode-group, opção recomendada calculada do preset e pré-selecionada.
                for screen in &screens[0..4] {
                    assert!(screen.required);
                    assert!(
                        !shows_choice_mode(screen.required, screen.kind, true),
                        "telas 1–4 não exibem options-mode-group"
                    );
                    let page_index = screen.pages[0];
                    seed_recommended_single(m, page_index, true, cx);
                    let choice = &m.manifest().choices[page_index];
                    let expected = RECOMMENDED_PRESET
                        .single
                        .iter()
                        .find(|&&(id, _)| id == choice.id)
                        .map(|&(_, opt)| opt)
                        .expect("toda tela obrigatória tem opção recomendada no preset");
                    assert!(m.options.contains(expected), "{expected} deve vir pré-selecionada");
                    let notes = option_notes(m, &screen.pages, true, false);
                    for opt in &choice.options {
                        assert_eq!(
                            notes[&opt.id].recommended,
                            opt.id == expected,
                            "(recomendado) calculado apenas para {expected}"
                        );
                    }
                }

                // Tela 5: exibe options-mode-group e todas as opções têm tooltip.
                let extras = &screens[4];
                assert!(!extras.required);
                assert!(shows_choice_mode(extras.required, extras.kind, true));
                assert!(
                    !shows_choice_mode(extras.required, extras.kind, false),
                    "somente leitura não exibe seletor"
                );
                let extras_notes = option_notes(m, &extras.pages, false, false);
                for &page_index in &extras.pages {
                    for opt in &m.manifest().choices[page_index].options {
                        let tip = extras_notes[&opt.id].tooltip.as_deref().unwrap_or("");
                        assert!(!tip.trim().is_empty(), "opção {} da tela 5 precisa de dica", opt.id);
                    }
                }

                // Usuário faz escolhas próprias nas telas 1 a 4 e suja a tela 5.
                m.choose_option(page_of(m, "defender-disable"), "defender-disable", cx);
                m.choose_option(page_of(m, "mitigations-disable"), "mitigations-disable", cx);
                m.choose_option(page_of(m, "auto-updates-default"), "auto-updates-default", cx);
                m.choose_option(page_of(m, "keyboard-shortcuts"), "keyboard-shortcuts", cx);
                m.choose_option(page_of(m, "disable-core-isolation"), "disable-core-isolation", cx);
                m.choose_option(page_of(m, "disable-phishing-protection"), "disable-phishing-protection", cx);
                m.choose_option(page_of(m, "remove-store"), "remove-store", cx);
                m.choose_option(page_of(m, "remove-snipping-tool"), "remove-snipping-tool", cx);
                m.choose_option(page_of(m, "install-another-browser"), "install-another-browser", cx);
                m.choose_option(page_of(m, "browser-firefox"), "browser-firefox", cx);

                // Aplicar Recomendado na Tela 5: muda só os itens da Tela 5 e mantém Telas 1–4 intactas!
                apply_recommended_on_pages(m, &extras.pages, cx);
                let effective: BTreeSet<String> = m.effective_options().into_iter().collect();

                for preserved in [
                    "defender-disable",
                    "mitigations-disable",
                    "auto-updates-default",
                    "keyboard-shortcuts",
                ] {
                    assert!(
                        effective.contains(preserved),
                        "Recomendado da Tela 5 não pode sobrescrever escolha anterior ({preserved})"
                    );
                }
                for expected_on in [
                    "disable-hibernation",
                    "disable-power-saving",
                    "disable-gamebar",
                    "vanta-power",
                    "vanta-memory",
                    "uninstall-edge",
                    "install-another-browser",
                    "browser-brave",
                ] {
                    assert!(effective.contains(expected_on), "{expected_on} deve ficar ligado no Recomendado");
                }
                for expected_off in [
                    "disable-core-isolation",
                    "disable-phishing-protection",
                    "remove-store",
                    "remove-snipping-tool",
                    "install-eclean",
                    "tools-on-logon",
                    "browser-firefox",
                ] {
                    assert!(!effective.contains(expected_off), "{expected_off} deve ficar desligado");
                }

                // Escolher manualmente zera só as caixas da Tela 5 e preserva Telas 1–4.
                clear_optional_choices_on_pages(m, &extras.pages, cx);
                let after_clear: BTreeSet<String> = m.effective_options().into_iter().collect();
                assert!(after_clear.contains("defender-disable"));
                assert!(after_clear.contains("keyboard-shortcuts"));
                assert!(!after_clear.contains("vanta-power"));
                assert!(!after_clear.contains("browser-brave"));
            });
        });
    }

    /// F3: `disable-core-isolation` começa travado; a caixa "Não jogo Valorant..." destrava;
    /// desmarcar a caixa volta o isolamento para ligado; o Recomendado nunca desliga o isolamento;
    /// reabrir um rascunho que já tem a opção marcada mantém a caixa marcada.
    #[test]
    fn core_isolation_valorant_guard_locks_unlocks_reverts_and_respects_recommended() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("core-isolation-guard");
            let model = installed_model(&mut cx, &temp, None, Facts::default());
            model.update(&mut cx, |m, _| {
                m.install_identity = Ok(InstallIdentity::Fresh);
                m.atlas = Ok(None);
                m.options.clear();
            });
            model.update(&mut cx, |m, cx| {
                let screens = m.option_screens();
                let extras = screens.last().unwrap();
                let sys_page = page_of(m, CORE_ISOLATION_OPTION);

                // 1) Começa travado com a explicação de segurança.
                let mut unlocked = false;
                let notes_locked = option_notes(m, &extras.pages, false, unlocked);
                let ci_note = &notes_locked[CORE_ISOLATION_OPTION];
                assert!(ci_note.locked, "disable-core-isolation deve começar travado");
                assert!(ci_note.consequence.is_some(), "explicação de segurança deve permanecer");

                // 2) Marcar a caixa do Valorant destrava a opção e permite desligar o isolamento.
                set_core_isolation_unlocked(&mut unlocked, true, sys_page, m, cx);
                assert!(unlocked);
                let notes_unlocked = option_notes(m, &extras.pages, false, unlocked);
                assert!(!notes_unlocked[CORE_ISOLATION_OPTION].locked, "caixa marcada destrava");
                m.choose_option(sys_page, CORE_ISOLATION_OPTION, cx);
                assert!(m.options.contains(CORE_ISOLATION_OPTION));

                // 3) Reabrir com a opção marcada no rascunho mantém a caixa marcada.
                let reopened_unlocked = m.options.contains(CORE_ISOLATION_OPTION);
                assert!(reopened_unlocked, "rascunho com disable-core-isolation já abre com caixa marcada");

                // 4) Desmarcar a caixa volta o isolamento para ligado (desmarca disable-core-isolation) e trava.
                set_core_isolation_unlocked(&mut unlocked, false, sys_page, m, cx);
                assert!(!unlocked);
                assert!(
                    !m.options.contains(CORE_ISOLATION_OPTION),
                    "desmarcar a caixa volta o Isolamento de Núcleo para ligado"
                );
                assert!(option_notes(m, &extras.pages, false, unlocked)[CORE_ISOLATION_OPTION].locked);

                // 5) Mesmo destravado e marcado, aplicar Recomendado nunca deixa o isolamento desligado.
                set_core_isolation_unlocked(&mut unlocked, true, sys_page, m, cx);
                m.choose_option(sys_page, CORE_ISOLATION_OPTION, cx);
                apply_recommended_on_pages(m, &extras.pages, cx);
                assert!(
                    !m.options.contains(CORE_ISOLATION_OPTION),
                    "Recomendado nunca desliga o Isolamento de Núcleo"
                );
            });
        });
    }

    /// F2 (regressão Hito): a primeira renderização das telas obrigatórias (1–4)
    /// nunca sobrescreve escolhas anteriores já salvas no rascunho quando diferentes do recomendado.
    #[test]
    fn first_render_of_required_screens_preserves_saved_draft_choices() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("draft-preserve-required");
            let model = installed_model(&mut cx, &temp, None, Facts::default());
            model.update(&mut cx, |m, cx| {
                m.install_identity = Ok(InstallIdentity::Fresh);
                m.atlas = Ok(None);
                m.options.clear();

                // Simula rascunho restaurado com escolhas não recomendadas nas 4 telas obrigatórias.
                m.choose_option(page_of(m, "defender-disable"), "defender-disable", cx);
                m.choose_option(page_of(m, "mitigations-disable"), "mitigations-disable", cx);
                m.choose_option(page_of(m, "auto-updates-default"), "auto-updates-default", cx);
                m.choose_option(page_of(m, "keyboard-shortcuts"), "keyboard-shortcuts", cx);

                assert!(!options_match_manifest_defaults(m));

                let screens = m.option_screens();
                // Em rascunho reaberto (allow_replace_manifest_default = false), nenhuma escolha muda.
                for screen in &screens[0..4] {
                    seed_recommended_single(m, screen.pages[0], false, cx);
                }
                for kept in [
                    "defender-disable",
                    "mitigations-disable",
                    "auto-updates-default",
                    "keyboard-shortcuts",
                ] {
                    assert!(m.options.contains(kept), "rascunho salvo deve preservar {kept}");
                }

                // Mesmo com allow_replace_manifest_default = true, escolhas não-default nunca são sobrescritas.
                for screen in &screens[0..3] {
                    seed_recommended_single(m, screen.pages[0], true, cx);
                }
                assert!(m.options.contains("defender-disable"));
                assert!(m.options.contains("mitigations-disable"));
                assert!(m.options.contains("auto-updates-default"));

                // Em fluxo novo com defaults virgens do manifesto, teclado assume keyboard-single.
                m.options = m.manifest().default_options().into_iter().collect();
                assert!(options_match_manifest_defaults(m));
                seed_recommended_single(m, page_of(m, "keyboard-shortcuts"), true, cx);
                assert!(m.options.contains("keyboard-single"));
            });
        });
    }

    /// F2 (regressão Hito + QA): em um fluxo novo vindo da Etapa 1, editar escolhas nas telas 1–3
    /// antes de visitar a Tela 4 (`Idiomas do teclado`) pela primeira vez ainda mantém a Tela 4
    /// pré-selecionada em `keyboard-single` (recomendado), sem sobrescrever edições nem rascunhos salvos.
    #[test]
    fn editing_earlier_screens_keeps_recommended_default_on_unvisited_keyboard_screen() {
        run_model_test(|mut cx| async move {
            let temp = TempDir::new("screen4-after-earlier-edits");
            let model = installed_model(&mut cx, &temp, None, Facts::default());
            model.update(&mut cx, |m, cx| {
                m.install_identity = Ok(InstallIdentity::Fresh);
                m.atlas = Ok(None);

                // 1) Fluxo novo vindo da Etapa 1 com defaults técnicos virgens do manifesto
                //    (manifesto traz `keyboard-shortcuts`, ainda não recomendado).
                m.options = m.manifest().default_options().into_iter().collect();
                m.option_screen = 0;
                assert!(options_match_manifest_defaults(m));
                assert!(m.options.contains("keyboard-shortcuts"));

                // Primeira entrada em Opções (Tela 1) semeia em lote todas as telas 1–4.
                let mut seeded = HashSet::new();
                seed_required_recommended_singles(m, &mut seeded, true, cx);
                assert_eq!(seeded.len(), 4, "todas as 4 telas obrigatórias devem ser semeadas juntas");
                assert!(
                    m.options.contains("keyboard-single"),
                    "Tela 4 já deve iniciar no recomendado keyboard-single"
                );

                // Usuário edita Tela 1 (Defender) e Tela 3 (Atualizações) antes de visitar a Tela 4.
                m.choose_option(page_of(m, "defender-disable"), "defender-disable", cx);
                m.option_screen = 2;
                m.choose_option(page_of(m, "auto-updates-default"), "auto-updates-default", cx);
                assert!(!options_match_manifest_defaults(m));

                // Ao chegar pela primeira vez na Tela 4 (Idiomas do teclado), re-renderizar preserva
                // as edições das telas 1–3 e mantém `keyboard-single` selecionado.
                m.option_screen = 3;
                seed_required_recommended_singles(m, &mut seeded, true, cx);
                assert!(m.options.contains("defender-disable"));
                assert!(m.options.contains("auto-updates-default"));
                assert!(
                    m.options.contains("keyboard-single"),
                    "Tela 4 deve continuar em keyboard-single após editar telas 1–3"
                );
                assert!(!m.options.contains("keyboard-shortcuts"));

                // Se o usuário escolher explicitamente `keyboard-shortcuts` na Tela 4 e voltar depois,
                // a escolha manual não é revertida.
                m.choose_option(page_of(m, "keyboard-shortcuts"), "keyboard-shortcuts", cx);
                seed_required_recommended_singles(m, &mut seeded, true, cx);
                assert!(m.options.contains("keyboard-shortcuts"));

                // 2) Rascunho reaberto diretamente em Opções (seen_ready_step = false) preserva todas
                //    as escolhas salvas, inclusive `keyboard-shortcuts`.
                let mut reopened_seeded = HashSet::new();
                seed_required_recommended_singles(m, &mut reopened_seeded, false, cx);
                assert!(m.options.contains("defender-disable"));
                assert!(m.options.contains("auto-updates-default"));
                assert!(m.options.contains("keyboard-shortcuts"));

                // 3) Rascunho parcial sem grupo de teclado preenchido: preserva as demais escolhas
                //    e preenche apenas o grupo faltante com `keyboard-single`.
                m.options.remove("keyboard-shortcuts");
                let mut partial_seeded = HashSet::new();
                seed_required_recommended_singles(m, &mut partial_seeded, false, cx);
                assert!(m.options.contains("defender-disable"));
                assert!(m.options.contains("auto-updates-default"));
                assert!(m.options.contains("keyboard-single"));
            });
        });
    }
}
