# Provenance of the Vanta artwork

Registro completo de origem, licenciamento e composição reprodutível das artes do Vanta (v1.1).
Atribuição curta incluída no `NOTICE`:
"Artes-base geradas com Google Flow; seleção, composição e acabamento pelo projeto Vanta."

## Artes-base sem assinatura incluídas no código-fonte (`2752x1536`, Google Flow)

Estas são as três saídas originais sem assinatura geradas no Google Flow (Nano Banana 2.1, 2K),
preservadas intactas no repositório como insumos editáveis (GPL-3.0):

| Arte-base no repositório | Dimensão | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `tools/art/bases/01-torii-nevoa-base.jpg` | 2752x1536 | 2 200 681 | `902c45b56e84c4195bf511383be425d333412804e6795c1080c5d601c5ff314a` |
| `tools/art/bases/02-pico-nebulosa-base.jpg` | 2752x1536 | 3 029 625 | `8f355fbf8fa244ac67ad8213ed7e82c6336fa0d207a81313d34ea0203e00ceac` |
| `tools/art/bases/03-eclipse-violeta-base.jpg` | 2752x1536 | 2 171 206 | `8074957985c1a698937a92ab8546e1c331c88a7149a171e4db67e739e2f05360` |

## Papéis de parede 2K finalistas (`2560x1440`, 16:9)

| Arquivo final | Título e numeração | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `vanta-01-torii-nevoa.jpg` | `N° 01 · TORII NÉVOA` | 737 406 | `9045819d4bb353f7c9aca7429c709b84a060e366dce1c219adc92db0ec3fbbe7` |
| `vanta-02-pico-nebulosa.jpg` | `N° 02 · PICO NEBULOSA` | 1 266 653 | `6e612edea3a973228c6f7c818fe1d9e825d361783739e9ce4da35b94178debbe` |
| `vanta-03-eclipse-violeta.jpg` | `N° 03 · ECLIPSE VIOLETA` | 684 503 | `49cc4d9e7e85b9e24224ff33d4ca91a5353267b9bab32d860f0cbbf40fd2edb1` |

## Cópias derivadas distribuídas neste repositório

| Arquivo no repositório | Origem | Formato | Bytes | SHA-256 |
| --- | --- | --- | ---: | --- |
| `app/resources/wallpapers/vanta-wallpaper-dark.png` | `vanta-03-eclipse-violeta.jpg` | PNG 2560x1440 (sem perdas) | 3 150 065 | `2f4bc3471546c6bf07959fdec68221d5bce63bdd6a673631c53c60ddff563558` |
| `app/resources/wallpapers/vanta-lockscreen-dark.png` | `vanta-01-torii-nevoa.jpg` | PNG 2560x1440 (sem perdas) | 3 204 229 | `0bfa87efd2e398f64e782ba0648c1a6e75a7a7d0535e445906e28acd60023e6a` |
| `app/assets/tools/bg/torii.jpg` | `vanta-01-torii-nevoa.jpg` | JPEG 2560x1440 (q=90) | 393 781 | `0c34ea33570bc6e78bde1957bf58617d34cb890a0a3fa98fe207fcd30b7aeae6` |
| `app/assets/tools/bg/nebulosa.jpg` | `vanta-02-pico-nebulosa.jpg` | JPEG 2560x1440 (q=90) | 777 316 | `d551034cda0ff4a5d7e9b43b9560ad44550ab9ae70719a1a7c495a8a185610fa` |
| `app/assets/tools/bg/eclipse.jpg` | `vanta-03-eclipse-violeta.jpg` | JPEG 2560x1440 (q=90) | 343 811 | `b1bc5bf464b49163a15d4d5878dcfdd1909db69a8cd8f10eb42ee0ec9d14bd81` |

## Origem, referências e direitos

- **Geração e ausência de referências de terceiros:** as três artes-base foram geradas do zero exclusivamente por
  prompts de texto originais do projeto Vanta no Google Flow (Google Gemini / Nano Banana 2.1, saída 2K `2752x1536`),
  **sem nenhuma imagem de referência de terceiros**, sem marcas, personagens ou obras protegidas.
- **Assinatura visual (`V A N T A` + barra `#7C4EE0` + numeração `01`/`02`/`03`):** o estilo tipográfico e geométrico
  da assinatura é concepção original do projeto Vanta (inspirado no guia visual interno `assin.png`, que NÃO é colado
  como bitmap nas artes finais). Nos arquivos distribuídos, a assinatura é renderizada 100% de forma programática por
  `tools/art/compose_wallpapers.py`, sem incorporar nenhum bitmap externo de terceiros, sob licença **GPL-3.0-only**.
- **Tipografia da assinatura e da numeração (`01`, `02`, `03`):** renderizada com as fontes **Geist Regular**
  (`app/assets/fonts/Geist-Regular.ttf`) e **Geist Medium** (`app/assets/fonts/Geist-Medium.ttf`), da família Geist
  (Vercel, Inc.), licenciadas sob **SIL Open Font License 1.1 (OFL-1.1)** — texto integral incluído em
  `app/licenses/fonts/Geist-OFL.txt` e compatível com a distribuição sob GPL-3.0.
- **Marca de proveniência (SynthID):** o projeto preserva a saída padrão do Google Flow nas bases em
  `tools/art/bases/` e no fluxo de exportação sem nenhuma etapa de remoção, filtragem ou obstrução de marca d'água
  digital ou SynthID.
- **Licenciamento:** a seleção, a composição, o script de acabamento, o layout tipográfico da assinatura e o arranjo
  final pertencem ao projeto Vanta e são distribuídos sob **GPL-3.0-only** (ver `LICENSE`). Como imagens geradas por
  IA não têm autoria humana reconhecida em todas as jurisdições, o projeto não reivindica exclusividade sobre a saída
  bruta do gerador além da seleção, composição e acabamento originais.

## Forma preferida de edição (GPL-3.0) e comando de reprodução testado

Todos os insumos para editar e regerar os 3 papéis de parede finais e os 5 derivados embarcados estão incluídos no
código-fonte (`Vanta-1.0.0-source.zip`):

- **Artes-base sem assinatura (`2752x1536`):** `tools/art/bases/01-torii-nevoa-base.jpg`,
  `tools/art/bases/02-pico-nebulosa-base.jpg` e `tools/art/bases/03-eclipse-violeta-base.jpg`.
- **Script de composição:** `tools/art/compose_wallpapers.py` (GPL-3.0-only, Python 3 + Pillow).
- **Fontes:** `app/assets/fonts/Geist-Regular.ttf` e `app/assets/fonts/Geist-Medium.ttf` (OFL-1.1).
- **Especificação visual:** recorte centralizado 16:9 para `2560x1440` (Lanczos), sobreposição em supersampling 2x no
  canto inferior direito (`88 px` direita, `86 px` base, livre da barra de tarefas), título `VANTA` (`Geist Regular`
  38 px, tracking 22 px, `#F4F2FA` 93%), barra `#7C4EE0` (`3 px` x 36% da largura), subtítulo numerado
  (`N° 01 · TORII NÉVOA`, `N° 02 · PICO NEBULOSA`, `N° 03 · ECLIPSE VIOLETA` em `Geist Medium` 14 px, tracking 2,6 px,
  `#F4F2FA` 78%) e sombra suave (`#06050A`, blur 4 px).

### Comando exato testado a partir da raiz do código-fonte extraído

Para reproduzir em uma pasta de saída separada (sem sobrescrever o repositório) e conferir os SHA-256 byte a byte:

```bash
python tools/art/compose_wallpapers.py --input-dir tools/art/bases --output-dir out-wallpapers/finais --repo-assets out-wallpapers/repo
```

Para regerar diretamente os 5 derivados dentro da árvore do repositório (`app/resources/wallpapers/` e
`app/assets/tools/bg/`):

```bash
python tools/art/compose_wallpapers.py --input-dir tools/art/bases --output-dir out-wallpapers/finais --sync-repo
```

## Prompts originais utilizados (Google Flow / Nano Banana 2.1, 16:9)

1. **`tools/art/bases/01-torii-nevoa-base.jpg` → `vanta-01-torii-nevoa.jpg`:**
   > Ultra-sharp cinematic dark night photography wallpaper in 16:9 widescreen, serene minimalist Japanese landscape. On the right third, the clean dark silhouette of a traditional wooden torii gate stands at the quiet edge of a still, mirror-like black lake wrapped in delicate low-lying violet mist (#7C4EE0). Behind it on the far right, the dark symmetrical silhouette of a distant volcanic mountain rises under a refined deep-purple starry night sky with faint violet cosmic glow (#8B5CF6, #A78BFA). The entire left half, center, and especially the calm dark water in the lower-center fade smoothly into tranquil obsidian-violet black (#0B0A10), ideal for desktop icons and a lock-screen clock. Photorealistic long-exposure atmosphere, OLED-ready blacks, refined contrast. No text, no watermark, no logos, no people, no characters, no lanterns with writing, no borders.
2. **`tools/art/bases/02-pico-nebulosa-base.jpg` → `vanta-02-pico-nebulosa.jpg`:**
   > Ultra-sharp cinematic dark night landscape wallpaper in 16:9 widescreen, refined minimalist astrophotography. Dark snow-dusted alpine mountain peaks rise in the middle-right distance, mirrored in a wide, glass-still dark mountain lake spanning the entire lower third. In the upper-right sky above the peaks, a rich, glowing violet Milky Way nebula in deep Vanta purple (#7C4EE0), luminous violet (#8B5CF6), and delicate lavender highlights (#A78BFA). The entire left half, center, and especially the lower-center lake surface are calm, smooth, and deeply shadowed in obsidian-violet black (#0B0A10), providing clean quiet space for desktop icons and a lock-screen clock. OLED-ready deep blacks, crisp stars, natural filmic grain, no magenta cast. No text, no watermark, no logos, no people, no characters, no borders.
3. **`tools/art/bases/03-eclipse-violeta-base.jpg` → `vanta-03-eclipse-violeta.jpg`:**
   > Ultra-sharp cinematic dark night landscape wallpaper in 16:9 widescreen, inspired by minimalist astrophotography. In the upper-right third, a dramatic total solar eclipse with a crisp, luminous violet-purple corona (#7C4EE0 blending into #8B5CF6 and soft lavender #A78BFA at the inner rim) hangs above jagged dark volcanic mountain ridges shrouded in subtle low mist on the lower right. The entire left half and center of the frame fade smoothly into calm, deep obsidian-violet darkness (#0B0A10) with very faint distant stars, leaving generous clean negative space for desktop icons and open windows. Rich OLED-ready blacks, refined lighting, photorealistic atmosphere, subtle filmic depth. No text, no watermark, no logos, no people, no characters, no borders.
