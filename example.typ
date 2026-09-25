// template.typ — Pandoc wrapper for slides-theme (Touying).
// Pipeline: Obsidian (Markdown) -> Pandoc -> Typst -> PDF.
//
// ALL frontmatter variables are OPTIONAL:
//   title, subtitle, author, date, institution,
//   accent-color ("#8B0000" or "8B0000"), title-font, body-font, cover-image,
//   toc (false hides the outline slide that otherwise follows the title).
// Missing values fall back to safe defaults inside slides-theme.typ;
// a missing/nonexistent cover-image yields a clean light title slide.

#import "@preview/touying:0.7.4": *
#import "slides-theme.typ": *

#let _accent-raw = "\#2c3e50"
#let _title-font-raw = "Oswald"
#let _body-font-raw = ""
#let _cover-raw = "assets/cover.jpg"
#let _aspect-raw = "16-9"

#show: slides-theme.with(
  aspect-ratio: _aspect-raw,
  accent: _accent-raw,
  title-font: _title-font-raw,
  body-font: _body-font-raw,
  // Only set info fields that are actually present: passing empty content to
  // touying's config-info would make markup-text() return none and crash
  // `set document(...)`. Conditional fields keep every value optional.
  config-info(
    title: [Готическая архитектура],
    subtitle: [От аббата Сугерия до «пламенеющей готики»],
    author: [Степан Ахвен],
    date: [2026],
    
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(cover-image: if _cover-raw != "" { _cover-raw } else { none })

#let _toc-entries = ((level: 1, text: [Введение]), (level: 2, text: [Что такое готика]), (level: 2, text: [Термин и определение]), (level: 1, text: [Конструкции]), (level: 2, text: [Нервюрный свод]), (level: 2, text: [Розетка]), (level: 2, text: [Хронология]), (level: 2, text: [Вертикальная диаграмма]), (level: 1, text: [Практика]), (level: 2, text: [Задание]), (level: 2, text: [Итог]), )
#toc-slide(_toc-entries)

#section-slide[Введение]

#content-slide(
  title: [Что такое готика],
  section: [Введение],
  body: [
Готический собор — «каменная книга» Средневековья: каждая пинакля,
каждый барабан окна прочитывался грамотным горожанином как строка
писания.


Новый стиль родился во Франции около 1140 года и за сто лет
распространился по всей Европе — от Парижа до Кёльна и Саламанки.

  ],
)

#content-slide(
  title: [Термин и определение],
  section: [Введение],
  body: [
Слово «готика» изначально было насмешкой: итальянские гуманисты называли
средневековое искусство «варварским», делом готов.


#quote(block: true)[
Готика — художественный стиль, возникший в середине XII века во Франции
на основе развития романской строительной техники.
]

  ],
)

#content-slide(
  title: [Термин и определение],
  section: [Введение],
  body: [
Содержание этого слайда разделено горизонтальной линией: обе страницы
получают один и тот же заголовок.


#strong[Строгое замечание]


Заголовок третьего уровня — это просто жирный текст, а не новый слайд.

  ],
)

#section-slide[Конструкции]

#content-slide(
  title: [Нервюрный свод],
  section: [Конструкции],
  images: ((path: "assets/vault.jpg", caption: [Нервюрный свод в Шартре]), ),
  body: [
Крестовый нервюрный свод позволил собрать распор в узких рёбрах и слегка
облегчить кладку между ними.

  ],
)

#content-slide(
  title: [Розетка],
  section: [Конструкции],
  body: [
Огромные розетки заполняли светом восточную часть храма; диаметр розетки


Шартрского собора превышает двенадцать метров.

  ],
)

#gallery-slide(
  ((path: "assets/chart.jpg", caption: [Динамика высоты нефа по десятилетиям]), (path: "assets/rose-window.jpg", caption: [Розетка Шартрского собора]), (path: "assets/rose-window.jpg", caption: [Розетка Шартрского собора]), (path: "assets/rose-window.jpg", caption: [Розетка Шартрского собора]), ),
)

#content-slide(
  title: [Хронология],
  section: [Конструкции],
  body: [
#figure(
align(center)[#table(
  columns: 3,
  align: (col, row) => (auto,auto,auto,).at(col),
  inset: (x: 0.95em, y: 0.72em),
  [Год], [Событие], [Место],
  [1143],
  [Первые нервюры],
  [Сен-Дени],
  [1194],
  [Пожар и новый Шартр],
  [Шартр],
  [1231],
  [Начало Амьенского собора],
  [Амьен],
)]
)

  ],
)

#content-slide(
  title: [Вертикальная диаграмма],
  section: [Конструкции],
  images: ((path: "assets/chart.jpg", caption: [Динамика высоты нефа по десятилетиям]), ),
  body: [
Диаграмма справа — вертикальная, поэтому движок отдаёт ей боковую
колонку на #strong[всю высоту];, а текст сжимается в левую.

  ],
)

#section-slide[Практика]

#content-slide(
  title: [Задание],
  section: [Практика],
  images: ((path: "assets/notre-dame.jpg", caption: [Западный фасад Нотр-Дам]), ),
  body: [
Опишите композицию западного фасада собора Парижской Богоматери по
прилагаемой фотографии: выделите ярусы, порталы, розетку и галерею
королей.

  ],
)

#focus-slide[Собор — это машина для света]
