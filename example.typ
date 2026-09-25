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

#let _accent-raw = "\#2c3e50"
#let _title-font-raw = "Oswald"
#let _body-font-raw = ""
#let _cover-raw = "assets/cover.jpg"
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
    title: [Готическая архитектура],
    subtitle: [Стремление к свету],
    author: [Кафедра истории искусства],
    date: [Октябрь 2026],
    institution: [Исторический факультет],
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(cover-image: if _cover-raw != "" { _cover-raw } else { none })

= Введение
<введение>
== Готический собор — «каменная книга»
<готический-собор-каменная-книга>
#strong[Готика] — стиль, зародившийся в Иль-де-Франс в середине XII
века.

- Современники звали его #emph[opus francigenum] — «французское дело»
- Слово «готика» — насмешка эпохи Возрождения

#figure([#image("assets/notre-dame.jpg", alt: "Собор Парижской Богоматери, западный фасад. Фото: Википедия")],
  caption: [
    Собор Парижской Богоматери, западный фасад. Фото: Википедия
  ]
)

== Термин и определение
<термин-и-определение>
#two-columns(columns: (58fr, 42fr))[#quote(block: true)[
Готический собор — это не здание, а образ мира, где свет заменяет стену,
а каркас — тяжесть камня.
]

#strong[Контрфорс] — наружная опора, принимающая распор свода.

#strong[Аркбутан] — полуарка, передающая распор от свода к контрфорсу.
][#figure([#image("assets/rose-window.jpg", alt: "Роза Сент-Шапель, XIII век")],
  caption: [
    Роза Сент-Шапель, XIII век
  ]
)
]
= Конструкции
<конструкции>
== Паутина смыслов
<паутина-смыслов>
Готическая конструкция — система, где #strong[нервюрный свод];,
#strong[аркбутан] и #strong[контрфорс] работают на общую цель. Схемы из
Excalidraw импортируются как обычные изображения:

#figure([#image("assets/vault.jpg", alt: "Схема распределения распора нервюрного свода (Excalidraw)")],
  caption: [
    Схема распределения распора нервюрного свода \(Excalidraw)
  ]
)

== Хронология
<хронология>
#figure(
align(center)[#table(
  columns: 3,
  align: (col, row) => (auto,auto,auto,).at(col),
  inset: (x: 0.95em, y: 0.72em),
  [Период], [Этап], [Характерная черта],
  [1140–1200],
  [Ранняя готика],
  [Сен-Дени, Лан],
  [1200–1280],
  [Высокая готика],
  [Шартр, Реймс, Амьен],
  [1280–1500],
  [Поздняя готика],
  [Пламенеющий стиль],
)]
)

= Практика
<практика>
== Задание
<задание>
#assignment[Сравните романский и готический соборы по трём критериям: стена, свет и
высота. Заполните таблицу или схему.

Подумайте, какую роль в этом различии играет #strong[аркбутан];.
][#figure([#image("assets/cover.jpg", alt: "Реймсский собор — эталон высокой готики")],
  caption: [
    Реймсский собор — эталон высокой готики
  ]
)
]
#focus-slide[
  «Свет — главный строительный материал готики»
]
