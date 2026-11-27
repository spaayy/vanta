//! Regras de apresentação do Vanta Tools que não dependem de tela: ordem das áreas, grupos de filtro de
//! Programas e filtros de Ajustes. Ficam aqui, e não no app, para ter teste (o app de ferramentas não roda testes).

use crate::tweaks::TweakState;

/// A ordem das áreas na navegação e no Início: a do desenho, não a ordem alfabética da chave interna.
pub const AREA_ORDER: [&str; 6] = ["Geral", "Interface", "Windows", "Jogos", "Avancado", "Seguranca"];

/// Posição da categoria na ordem do desenho; o que não está na lista vai para o fim.
pub fn area_rank(category: &str) -> usize {
    AREA_ORDER.iter().position(|c| *c == category).unwrap_or(AREA_ORDER.len())
}

/// Os chips de Programas, na ordem em que aparecem (depois de "Todos"): uma linha só.
pub const PROGRAM_CHIPS: [&str; 6] = [
    "Jogos",
    "Comunicação",
    "Periféricos e áudio",
    "Gravação e mídia",
    "Ferramentas",
    "Seus apps",
];

/// O chip a que uma categoria do catálogo pertence. IA, Dev e terminal, Rede e Driver de vídeo ficam dentro de
/// "Ferramentas"; as seções da lista continuam com o nome de cada categoria.
pub fn chip_of(category: &str) -> &str {
    match category {
        "IA" | "Dev e terminal" | "Rede" | "Driver de vídeo" => "Ferramentas",
        other => other,
    }
}

/// Texto procurado no nome, sem diferenciar maiúsculas; filtro vazio deixa tudo.
pub fn name_matches(name: &str, filter: &str) -> bool {
    let filter = filter.trim();
    filter.is_empty() || name.to_lowercase().contains(&filter.to_lowercase())
}

/// A barra Todos / Ativos / Inativos de Ajustes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum StateFilter {
    #[default]
    All,
    On,
    Off,
}

impl StateFilter {
    /// "Misto" conta como inativo: o padrão Vanta não está todo aplicado.
    pub fn keeps(self, state: TweakState) -> bool {
        match self {
            StateFilter::All => true,
            StateFilter::On => state == TweakState::On,
            StateFilter::Off => state != TweakState::On,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn areas_follow_the_design_order_not_the_alphabet() {
        let mut keys = ["Avancado", "Geral", "Interface", "Jogos", "Seguranca", "Windows"];
        keys.sort_by_key(|k| area_rank(k));
        assert_eq!(keys, ["Geral", "Interface", "Windows", "Jogos", "Avancado", "Seguranca"]);
        assert_eq!(area_rank("desconhecida"), AREA_ORDER.len(), "o desconhecido vai para o fim");
    }

    #[test]
    fn eight_chips_with_the_small_categories_inside_tools() {
        assert_eq!(PROGRAM_CHIPS.len() + 1, 7, "Todos + 6");
        for inner in ["IA", "Dev e terminal", "Rede", "Driver de vídeo"] {
            assert_eq!(chip_of(inner), "Ferramentas", "{inner}");
        }
        for own in PROGRAM_CHIPS {
            assert_eq!(chip_of(own), own);
        }
    }

    #[test]
    fn the_name_filter_ignores_case_and_blank_keeps_everything() {
        assert!(name_matches("Mozilla Firefox", "fire"));
        assert!(name_matches("Mozilla Firefox", "  FOX "));
        assert!(!name_matches("Mozilla Firefox", "chrome"));
        assert!(name_matches("Qualquer", "   "));
    }

    #[test]
    fn the_state_filter_counts_mixed_as_inactive() {
        assert!(StateFilter::All.keeps(TweakState::Mixed));
        assert!(StateFilter::On.keeps(TweakState::On) && !StateFilter::On.keeps(TweakState::Mixed));
        assert!(StateFilter::Off.keeps(TweakState::Mixed) && StateFilter::Off.keeps(TweakState::Off));
        assert!(!StateFilter::Off.keeps(TweakState::On));
    }
}
