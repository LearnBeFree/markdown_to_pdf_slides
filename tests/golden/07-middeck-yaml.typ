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
    
    
    
    
    
    
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(
  cover-image: if _cover-raw != "" { _cover-raw } else { none },
  cover-format: if _cover-fmt-raw != "" { _cover-fmt-raw } else { auto },
)

#let _toc-entries = ((level: 2, text: [Слайд один]), (level: 2, text: [Слайд два]), )
#toc-slide(_toc-entries)

#content-slide(
  title: [Слайд один],
  body: [
Текст.

  ],
)

#content-slide(
  title: [Слайд один],
  body: [
foo: bar baz: qux

  ],
)

#content-slide(
  title: [Слайд два],
  body: [
Блок, выглядящий как YAML, — это просто текст между разделителями
слайдов.

  ],
)
