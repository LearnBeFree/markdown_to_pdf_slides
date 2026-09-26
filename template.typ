// template.typ — Pandoc wrapper for slides-theme (Touying).
// Pipeline: Obsidian (Markdown) -> Pandoc -> Typst -> PDF.
//
// ALL frontmatter variables are OPTIONAL:
//   title, subtitle, author, date, institution,
//   accent-color ("#8B0000" or "8B0000"), title-font, body-font, cover-image,
//   toc (false hides the outline slide that otherwise follows the title),
//   aspect-ratio ("16-9"; anything not W-H shaped falls back to 16-9),
//   lang (BCP-47, defaults to "ru"; drives hyphenation/quotes).
// Missing values fall back to safe defaults inside slides-theme.typ;
// a missing/nonexistent cover-image yields a clean light title slide.
//
// The build scripts also pass theme-dir=<absolute theme dir> so the
// generated .typ can live next to the source markdown anywhere on disk;
// without it the theme is imported as a sibling file.

#import "@preview/touying:0.7.4": *
$if(theme-dir)$
#let _theme-file = "$theme-dir$/slides-theme.typ"
$else$
#let _theme-file = "slides-theme.typ"
$endif$
#import (_theme-file): *

#let _accent-raw = "$if(accent-color)$$accent-color$$endif$"
#let _title-font-raw = "$if(title-font)$$title-font$$endif$"
#let _body-font-raw = "$if(body-font)$$body-font$$endif$"
#let _cover-raw = "$if(cover-image)$$cover-image$$endif$"
#let _aspect-raw = "$if(aspect-ratio)$$aspect-ratio$$else$16-9$endif$"

#show: slides-theme.with(
  aspect-ratio: _aspect-raw,
  accent: _accent-raw,
  title-font: _title-font-raw,
  body-font: _body-font-raw,
  $if(lang)$lang: "$lang$",$endif$
  // Only set info fields that are actually present: passing empty content to
  // touying's config-info would make markup-text() return none and crash
  // `set document(...)`. Conditional fields keep every value optional.
  config-info(
    $if(title)$title: [$title$],$endif$
    $if(subtitle)$subtitle: [$subtitle$],$endif$
    $if(author)$author: [$for(author)$$author$$sep$, $endfor$],$endif$
    $if(date)$date: [$date$],$endif$
    $if(institution)$institution: [$institution$],$endif$
    $if(contact)$contact: [$contact$],$endif$
  ),
)

// Custom title slide (always rendered; cover image is optional).
#title-slide(cover-image: if _cover-raw != "" { _cover-raw } else { none })

$body$
