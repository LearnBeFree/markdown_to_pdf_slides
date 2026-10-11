// template.typ — Pandoc wrapper for slides-theme (Touying).
// Pipeline: Obsidian (Markdown) -> Pandoc -> Typst -> PDF.
//
// ALL frontmatter variables are OPTIONAL:
//   title, subtitle, author, date, institution,
//   accent-color ("#8B0000" or "8B0000"), title-font, body-font, cover-image,
//   toc (false hides the outline slide that otherwise follows the title),
//   progress-bar (true shows the footer progress bar on content slides;
//     section dividers always have it; default: hidden on content slides),
//   dark_theme (true -> dark palette; accent color stays the same;
//     default: light/white theme),
//   aspect-ratio ("16-9"; anything not W-H shaped falls back to 16-9),
//   lang (BCP-47, defaults to "ru"; drives hyphenation/quotes).
// Missing values fall back to safe defaults inside slides-theme.typ;
// a missing/nonexistent cover-image yields a clean light title slide.
//
// The build stages a copy of slides-theme.typ next to the generated .typ,
// so the import is a plain sibling reference: no absolute theme paths and
// no env vars (both mangle non-ASCII paths on Windows).

#import "@preview/touying:0.7.4": *
#import "slides-theme.typ": *

#let _accent-raw = ""
#let _focus-accent-raw = ""
#let _title-font-raw = ""
#let _body-font-raw = ""
#let _cover-raw = ""
#let _cover-fmt-raw = ""
#let _aspect-raw = "16-9"
#let _progress-raw = ""
#let _dark-raw = ""

#show: slides-theme.with(
  aspect-ratio: _aspect-raw,
  accent: _accent-raw,
  focus-accent: _focus-accent-raw,
  title-font: _title-font-raw,
  body-font: _body-font-raw,
  progress-bar: _progress-raw,
  dark-theme: _dark-raw,
  
  // Only set info fields that are actually present: passing empty content to
  // touying's config-info would make markup-text() return none and crash
  // `set document(...)`. Conditional fields keep every value optional.
  config-info(
    title: [Заголовки без пустых строк],
    
    
    
    
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(
  cover-image: if _cover-raw != "" { _cover-raw } else { none },
  cover-format: if _cover-fmt-raw != "" { _cover-fmt-raw } else { auto },
)

#let _toc-entries = ((level: 1, text: [Первый раздел]), (level: 2, text: [Слайд первый]), (level: 2, text: [Заголовок без пустой строки перед ним]), (level: 2, text: [После линии тоже без пустой строки]), (level: 2, text: [Пустой фокус]), (level: 2, text: [Обычный хвост]), (level: 2, text: [Между линиями]), (level: 2, text: [После второй линии]), )
#toc-slide(_toc-entries)

#section-slide[Первый раздел]

#content-slide(
  title: [Слайд первый],
  section: [Первый раздел],
  body: [
Текстовый абзац.

  ],
)

#content-slide(
  title: [Заголовок без пустой строки перед ним],
  section: [Первый раздел],
  body: [
- Этот слайд начался с заголовка, идущего сразу за текстом.

  ],
)

#content-slide(
  title: [После линии тоже без пустой строки],
  section: [Первый раздел],
  body: [
Ещё текст.

  ],
)

#focus-slide[Пустой фокус]

#content-slide(
  title: [Обычный хвост],
  section: [Первый раздел],
  body: [
- Конец.

  ],
)

#content-slide(
  title: [Между линиями],
  section: [Первый раздел],
  body: [
- Текст между двумя линиями-разделителями не должен превращаться в
  таблицу и проглатывать заголовки.


Около 2100 лет до н.э. случилась засуха.

  ],
)

#content-slide(
  title: [После второй линии],
  section: [Первый раздел],
  body: [
- Всё ещё отдельные слайды.

  ],
)
