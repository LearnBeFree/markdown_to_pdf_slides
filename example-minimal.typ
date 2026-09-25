// template.typ — Pandoc wrapper for slides-theme (Touying).
// Pipeline: Obsidian (Markdown) -> Pandoc -> Typst -> PDF.
//
// ALL frontmatter variables are OPTIONAL:
//   title, subtitle, author, date, institution,
//   accent-color ("#8B0000" or "8B0000"), title-font, body-font, cover-image.
// Missing values fall back to safe defaults inside slides-theme.typ;
// a missing/nonexistent cover-image yields a clean light title slide.

#import "@preview/touying:0.7.4": *
#import "slides-theme.typ": *

#let _accent-raw = "не-цвет"
#let _title-font-raw = ""
#let _body-font-raw = ""
#let _cover-raw = ""
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
    title: [Романский стиль],
    
    
    
    
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(cover-image: if _cover-raw != "" { _cover-raw } else { none })

#section-slide[Устойчивость]

#content-slide(
  title: [Всё по умолчанию],
  section: [Устойчивость],
  body: [
Этот файл проверяет деградацию: неверный цвет акцента и несуществующая
обложка должны незаметно подмениться безопасными значениями.


Заголовков первого и второго уровней ровно столько, сколько нужно, а
горизонтальных линий нет вовсе.

  ],
)

#content-slide(
  title: [Всё по умолчанию],
  section: [Устойчивость],
  body: [
А это второй слайд с тем же заголовком — проверка разделителя без
картинок и без таблиц.

  ],
)

#section-slide[Основы]

#content-slide(
  title: [Монастырь как центр мира],
  section: [Основы],
  body: [
Толстые стены, маленькие окна, цилиндрические своды — романский храм
построен как крепость веры.

  ],
)

#content-slide(
  title: [Термин и определение],
  section: [Основы],
  body: [
Романский стиль — первое общеевропейское художественное направление,
сложившееся после распада каролингской империи.


#strong[Примечание]


Жирный текст вместо заголовка третьего уровня.

  ],
)

#content-slide(
  title: [Задание],
  section: [Основы],
  body: [
Найдите на фотографии церковь Сен-Мартен — изображение потеряно, поэтому
здесь появится аккуратная заглушка.


#box(width: 100%, height: 110pt, stroke: (paint: rgb("#9A9186"), thickness: 0.8pt, dash: "dashed"), radius: 4pt)[#align(center + horizon)[#text(fill: rgb("#9A9186"), size: 0.8em)[нет изображения: assets/missing.jpg]]]
  ],
)
