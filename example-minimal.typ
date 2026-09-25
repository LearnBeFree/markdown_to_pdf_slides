// template.typ — Pandoc wrapper for the art-theme (Touying).
// Pipeline: Obsidian (Markdown) -> Pandoc -> Typst -> PDF.
//
// ALL frontmatter variables are OPTIONAL:
//   title, subtitle, author, date, institution,
//   accent-color ("#8B0000" or "8B0000"), title-font, body-font, cover-image.
// Missing values fall back to safe defaults inside art-theme.typ;
// a missing/nonexistent cover-image yields a clean light title slide.
//
// NOTE: accent-color/title-font/body-font/cover-image are emitted as Typst
// STRING literals. Pandoc escapes special chars (# _ * ...) with a backslash;
// the theme strips those backslashes before use, so "#2c3e50" and
// "assets/my_cover.jpg" both survive intact.

#import "@preview/touying:0.7.4": *
#import "art-theme.typ": *

#let _accent-raw = "не-цвет"
#let _title-font-raw = ""
#let _body-font-raw = ""
#let _cover-raw = ""
#let _aspect-raw = "16-9"

#show: art-theme.with(
  aspect-ratio: _aspect-raw,
  accent: _accent-raw,
  title-font: _title-font-raw,
  body-font: _body-font-raw,
  // Only set info fields that are actually present: passing empty content to
  // touying's config-info would make markup-text() return none and crash
  // `set document(...)`. Conditional fields keep every value optional.
  config-info(
    title: [Романский стиль],
    
    
    
    
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(cover-image: if _cover-raw != "" { _cover-raw } else { none })

= Устойчивость
<устойчивость>
== Всё по умолчанию
<всё-по-умолчанию>
Этот слайд собран из «ленивого» frontmatter: отсутствуют `subtitle`,
`author`, `date` и `title-font`.

- `cover-image` ведёт на несуществующий файл — тема строит титул без
  картинки
- `accent-color` содержит мусор — берётся дефолтный бордовый
  #strong[\#8B0000]
- Заголовки — #strong[Yeseva One];, основной текст —
  #strong[Philosopher]

Компиляция проходит без единой ошибки.

= Основы
<основы>
== Монастырь как центр мира
<монастырь-как-центр-мира>
#strong[Романский стиль] \(X–XII века) — первая общеевропейская
архитектурная эпоха после Рима.

#emph[Militans Ecclesia];: монастырь — крепость духа.

#figure([#image("assets/chart.jpg", alt: "Типичная романская капитель (заглушка)")],
  caption: [
    Типичная романская капитель \(заглушка)
  ]
)

== Термин и определение
<термин-и-определение>
#two-columns(columns: (55fr, 45fr))[#quote(block: true)[
Романская арка — полукруглая и тяжёлая: она опирается на массивную
стену.
]

#strong[Клеристорий] — верхний ярус стен с окнами.
][#figure([#image("assets/chart.jpg", alt: "Интерьер романской церкви")],
  caption: [
    Интерьер романской церкви
  ]
)
]
== Задание
<задание>
#assignment[Перечислите три отличия романского храма от готического.
][#figure([#image("assets/chart.jpg", alt: "Схема романской церкви (Excalidraw)")],
  caption: [
    Схема романской церкви \(Excalidraw)
  ]
)
]
