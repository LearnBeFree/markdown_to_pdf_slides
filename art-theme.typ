// art-theme.typ — «Art History» theme for Touying (Typst).
// Light, cozy, serious theme for history / art-history slides in Russian.
// Every parameter is optional and falls back to a safe default.
// Written for Typst 0.14 (no plain(), no str.lower(), no regex.test()).

#import "@preview/touying:0.7.4": *

// ---------------------------------------------------------------------------
// Palette & constants
// ---------------------------------------------------------------------------

#let _default-accent = rgb("#8B0000") // burgundy fallback
#let _paper = rgb("#FBF8F1")          // warm ivory page background
#let _ink = rgb("#2B2723")            // warm dark gray body text
#let _cream = rgb("#FAF6EC")          // light text over photos / accent fills
#let _soft = rgb("#857C72")           // muted secondary text

#let _page-x = 2.4em                  // horizontal margin (header/footer pad to match)

// Max height reserved for figure images (keeps them inside the slide body).
#let _img-h-standalone = 210pt        // image on a normal text+figure slide
#let _img-h-column = 235pt            // image inside a column / assignment

// ---------------------------------------------------------------------------
// Safe resolvers (never crash on empty / weird / Pandoc-escaped input)
// ---------------------------------------------------------------------------

// Extract readable text from content by stripping repr()'s markup.
// (Typst 0.14 has no plain() and no str(content).)
#let _cstr(c) = {
  if c == none { return "" }
  if type(c) == str { return c }
  if type(c) == content {
    return repr(c).replace("[", "").replace("]", "").replace("\\", "").trim()
  }
  return ""
}

// Is this optional value effectively empty/absent?
#let _is-empty(c) = {
  if c == none { return true }
  if type(c) == str { return c.trim() == "" }
  if type(c) == content {
    if c == [] { return true }
    return _cstr(c) == ""
  }
  return false
}

#let _has(c) = not _is-empty(c)

// Accepts color, hex string ("#8B0000", "8B0000", "\#8B0000", "abc"),
// content, or none. Anything unparseable -> fallback. (rgb accepts upper/lower.)
#let _resolve-color(raw, fallback) = {
  if raw == none or raw == auto { return fallback }
  if type(raw) == color { return raw }
  let s = if type(raw) == content { _cstr(raw) } else { str(raw) }
  s = s.replace("\\", "").replace("#", "").replace(" ", "").replace("\"", "").replace("'", "")
  if s.matches(regex("^[0-9a-fA-F]{6}$")).len() > 0 { return rgb("#" + s) }
  if s.matches(regex("^[0-9a-fA-F]{3}$")).len() > 0 {
    let e = s.at(0) + s.at(0) + s.at(1) + s.at(1) + s.at(2) + s.at(2)
    return rgb("#" + e)
  }
  return fallback
}

// Accepts font name (str), array of names, content, or none.
// Always returns a priority list ending with the theme defaults, so missing
// fonts degrade gracefully instead of crashing.
#let _resolve-fonts(raw, defaults) = {
  let names = ()
  let clean(n) = str(n).replace("\\", "").replace("\"", "").replace("'", "").trim()
  if raw != none and raw != auto {
    if type(raw) == str {
      let t = clean(raw)
      if t != "" { names.push(t) }
    } else if type(raw) == content {
      let t = clean(_cstr(raw))
      if t != "" { names.push(t) }
    } else if type(raw) == array {
      for n in raw {
        let t = clean(n)
        if t != "" and not (t in names) { names.push(t) }
      }
    }
  }
  for d in defaults { if not (d in names) { names.push(d) } }
  names
}

// Clean a Pandoc-escaped path back to a real filesystem path.
#let _clean-path(p) = str(p).replace("\\", "").replace("\"", "").trim()

// ---------------------------------------------------------------------------
// Decorations
// ---------------------------------------------------------------------------

// Classic "rule — diamonds — rule" ornament.
#let _ornament(paint, width: 44%) = align(center, box(width: width, grid(
  columns: (1fr, auto, auto, auto, 1fr),
  column-gutter: 0.5em,
  align(horizon, line(length: 100%, stroke: 0.8pt + paint.lighten(40%))),
  align(horizon, box(rotate(45deg, rect(width: 3.4pt, height: 3.4pt, fill: paint.lighten(20%))))),
  align(horizon, box(rotate(45deg, rect(width: 5pt, height: 5pt, fill: paint)))),
  align(horizon, box(rotate(45deg, rect(width: 3.4pt, height: 3.4pt, fill: paint.lighten(20%))))),
  align(horizon, line(length: 100%, stroke: 0.8pt + paint.lighten(40%))),
)))

// ---------------------------------------------------------------------------
// Public layout helpers (used by the Pandoc Lua filter as raw Typst)
// ---------------------------------------------------------------------------

/// Two (or more) columns. `columns` accepts any Typst track sizes:
/// `#two-columns(columns: (60%, 1fr))[left][right]`
#let two-columns(columns: (1fr, 1fr), gutter: 1.6em, ..bodies) = {
  let cells = bodies.pos().map(b => block(width: 100%)[
    #show figure.where(kind: image): set image(width: 100%, height: _img-h-column, fit: "contain")
    #b
  ])
  grid(columns: columns, column-gutter: gutter, ..cells)
}

/// «Задание» slide body: text on the left, image(s) on the right.
#let assignment(left, right) = two-columns(columns: (1fr, 0.85fr), gutter: 2.2em, left, right)

// ---------------------------------------------------------------------------
// Slide functions
// ---------------------------------------------------------------------------

#let slide(
  title: auto,
  config: (:),
  repeat: auto,
  setting: body => body,
  composer: auto,
  ..bodies,
) = touying-slide-wrapper(self => {
  if title != auto { self.store.title = title }
  let accent = self.colors.primary
  let ink = self.colors.neutral-darkest
  let hfonts = self.store.heading-fonts

  let header(self) = {
    set align(top + left)
    show: components.cell
    pad(x: _page-x, top: 0.7em, bottom: 0.45em)[
      #grid(
        columns: (1fr, auto),
        column-gutter: 1em,
        // Fixed-height cells keep the rule at the same y on every slide
        // (so the «ЗАДАНИЕ» badge, which is shorter than the big title, does
        // not push the rule up and change the gap above the body).
        box(height: 2.0em, align(left + horizon)[
          #context {
            let h = utils.current-heading(level: 2)
            let tstr = if h != none { _cstr(h.body) } else if self.store.title != none {
              _cstr(self.store.title)
            } else { "" }
            if tstr.matches(regex("(?i)^ *задание *$")).len() > 0 {
              box(
                fill: accent,
                radius: 2.5pt,
                inset: (x: 0.8em, y: 0.22em),
              )[#set text(font: hfonts, fill: _cream, size: 0.62em, tracking: 0.14em); ЗАДАНИЕ]
            } else {
              set text(font: hfonts, size: 1.6em, fill: accent.darken(12%))
              if _has(self.store.title) {
                utils.call-or-display(self, self.store.title)
              } else {
                utils.display-current-heading(level: 2)
              }
            }
          }
        ]),
        box(height: 2.0em, align(right + horizon)[
          #set text(size: 0.5em, fill: _soft, tracking: 0.06em)
          #utils.display-current-heading(level: 1)
        ]),
      )
      #v(0.45em)
      #line(length: 100%, stroke: 1.3pt + accent.lighten(25%))
    ]
  }

  let footer(self) = {
    set align(bottom)
    show: components.cell
    pad(x: _page-x, y: 0.45em)[
      #grid(
        columns: (1fr, auto),
        {
          set text(size: 0.48em, fill: _soft)
          utils.call-or-display(self, self.store.footer)
        },
        {
          set text(size: 0.52em, fill: ink.lighten(30%))
          context utils.slide-counter.display() + " / " + utils.last-slide-number
        },
      )
    ]
  }

  self = utils.merge-dicts(
    self,
    config-page(header: header, footer: footer),
    config,
  )
  touying-slide(self: self, repeat: repeat, setting: setting, composer: composer, ..bodies)
})

#let title-slide(config: (:), cover-image: none, ..args) = touying-slide-wrapper(self => {
  let accent = self.colors.primary
  let ink = self.colors.neutral-darkest
  let hfonts = self.store.heading-fonts
  let info = self.info + args.named()
  let cover = if _has(cover-image) { _clean-path(cover-image) } else { none }

  // author · date · institution line, joined with a middle dot
  let meta-parts = ()
  if _has(info.author) { meta-parts.push(info.author) }
  if _has(info.date) { meta-parts.push(utils.display-info-date(self)) }
  if _has(info.institution) { meta-parts.push(info.institution) }
  let meta = if meta-parts.len() > 0 {
    meta-parts.fold([], (acc, p) => if acc == [] { p } else { acc + h(0.55em) + [·] + h(0.55em) + p })
  } else { none }

  if cover != none {
    // ---- full-bleed photo title slide ----
    self = utils.merge-dicts(
      self,
      config-common(freeze-slide-counter: true),
      config-page(
        margin: 0em,
        header: none,
        footer: none,
        fill: rgb("#1A150F"),
        background: {
          set image(fit: "cover", width: 100%, height: 100%)
          image(cover)
          place(top + left, rect(
            width: 100%,
            height: 100%,
            fill: gradient.linear(
              rgb("#150F0A").transparentize(55%),
              rgb("#150F0A").transparentize(78%),
              rgb("#150F0A").transparentize(10%),
              angle: 90deg,
            ),
          ))
        },
      ),
      config,
    )
    let body = align(bottom + left, pad(x: 2.8em, y: 2.6em)[
      #set text(fill: _cream)
      #if _has(info.title) {
        set text(font: hfonts, size: 2.4em)
        block(width: 84%, info.title)
        v(0.5em)
        line(length: 6em, stroke: 2.2pt + _cream.transparentize(25%))
        v(0.6em)
      }
      #if _has(info.subtitle) {
        set text(size: 1em, style: "italic", fill: _cream.transparentize(12%))
        block(width: 70%, info.subtitle)
      }
      #if meta != none {
        v(1.1em)
        set text(size: 0.55em, fill: _cream.transparentize(30%))
        meta
      }
    ])
    touying-slide(self: self, body)
  } else {
    // ---- clean light title slide with a double frame ----
    self = utils.merge-dicts(
      self,
      config-common(freeze-slide-counter: true),
      config-page(
        margin: 0em,
        header: none,
        footer: none,
        fill: _paper,
        background: {
          place(top + left, dx: 0.9em, dy: 0.9em, rect(
            width: 100% - 1.8em, height: 100% - 1.8em,
            stroke: 1.2pt + accent.lighten(50%),
          ))
          place(top + left, dx: 1.15em, dy: 1.15em, rect(
            width: 100% - 2.3em, height: 100% - 2.3em,
            stroke: 0.5pt + accent.lighten(72%),
          ))
        },
      ),
      config,
    )
    let body = align(center + horizon)[
      #set text(fill: ink)
      #_ornament(accent, width: 46%)
      #v(1.4em)
      #if _has(info.title) {
        set text(font: hfonts, size: 2.2em, fill: accent.darken(8%))
        block(width: 78%, info.title)
      }
      #if _has(info.subtitle) {
        v(0.75em)
        set text(size: 0.95em, style: "italic", fill: _soft)
        block(width: 70%, info.subtitle)
      }
      #v(1.4em)
      #_ornament(accent, width: 46%)
      #if meta != none {
        v(1.7em)
        set text(size: 0.55em, fill: _soft)
        meta
      }
    ]
    touying-slide(self: self, body)
  }
})

#let new-section-slide(config: (:), level: 1, numbered: true, body) = touying-slide-wrapper(self => {
  let accent = self.colors.primary
  let hfonts = self.store.heading-fonts
  self = utils.merge-dicts(
    self,
    config-common(freeze-slide-counter: true),
    config-page(
      fill: _paper,
      margin: 2em,
      header: none,
      footer: none,
      background: place(bottom + left, rect(
        width: 100%, height: 5pt,
        fill: gradient.linear(accent.lighten(45%), accent, accent.lighten(45%)),
      )),
    ),
    config,
  )
  // Symmetric ornaments + explicit-pt gaps keep the word centred on the page.
  // The gaps differ by a few pt (27 vs 17) as an OPTICAL correction: a text
  // line box reserves descent space below the baseline, so the visible glyphs
  // sit ~5pt above the box centre. Nudging the box down puts the INK centred.
  let main = align(center + horizon)[
    #_ornament(accent, width: 30%)
    #v(27pt)
    #set text(font: hfonts, size: 1.7em, fill: accent.darken(10%))
    #utils.display-current-heading(level: level, numbered: false, style: auto)
    #v(17pt)
    #_ornament(accent, width: 30%)
  ]
  touying-slide(self: self, main)
})

#let focus-slide(config: (:), body) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config-common(freeze-slide-counter: true),
    config-page(fill: self.colors.primary, margin: 2.5em, header: none, footer: none),
    config,
  )
  set text(fill: _cream, size: 1.6em, font: self.store.heading-fonts)
  touying-slide(self: self, align(center + horizon, body))
})

// ---------------------------------------------------------------------------
// Theme entry point
// ---------------------------------------------------------------------------

#let art-theme(
  aspect-ratio: "16-9",
  accent: auto,        // color | hex str | none  -> default burgundy
  title-font: auto,    // str | array | none      -> default "Yeseva One"
  body-font: auto,     // str | array | none      -> default "Philosopher"
  footer: none,        // content | self => content | none -> presentation title
  ..args,
  body,
) = {
  let accent-color = _resolve-color(accent, _default-accent)
  let heading-fonts = _resolve-fonts(title-font, (
    "Yeseva One", "Liberation Serif", "Caladea", "FreeSerif",
  ))
  let body-fonts = _resolve-fonts(body-font, (
    "Philosopher", "Liberation Sans", "Carlito", "FreeSans",
  ))

  // ---- global typography & content styling ----
  set text(size: 20pt, font: body-fonts, fill: _ink, lang: "ru")
  set par(justify: true, leading: 0.7em)

  show heading: set text(font: heading-fonts, fill: accent-color, weight: "regular")
  show heading.where(level: 1): set text(size: 1.5em)
  show heading.where(level: 2): set text(size: 1.1em)
  show heading.where(level: 3): set text(size: 0.95em)

  show strong: set text(fill: accent-color)
  show link: set text(fill: accent-color.darken(10%))

  // inline `code` / field names: accent-tinted, slightly smaller
  show raw.where(block: false): set text(fill: accent-color.darken(12%), size: 0.82em)
  show raw.where(block: true): it => block(
    width: 100%,
    fill: accent-color.lighten(94%),
    stroke: 0.6pt + accent-color.lighten(70%),
    radius: 3pt,
    inset: 0.7em,
    above: 0.7em,
    below: 0.7em,
    it,
  )

  set list(
    indent: 1.1em,
    body-indent: 0.4em,
    marker: box(baseline: 22%, rect(width: 3.6pt, height: 3.6pt, fill: accent-color.lighten(20%))),
  )
  set enum(
    indent: 1.1em,
    body-indent: 0.4em,
    numbering: n => text(fill: accent-color, font: heading-fonts)[#n.],
  )

  // figures: no numbering, italic accent-colored captions, slide-fit sizing.
  // `fit: contain` inside a wide box => images are height-limited (no vertical
  // overflow) and centered, regardless of portrait/landscape aspect ratio.
  set figure(numbering: none)
  show figure: set align(center)
  show figure.where(kind: image): set image(width: 100%, height: _img-h-standalone, fit: "contain")
  show figure.caption: set text(size: 0.6em, style: "italic", fill: accent-color.darken(15%))

  // cozy authentic blockquote
  show quote: it => block(
    width: 100%,
    above: 0.9em,
    below: 0.9em,
    fill: accent-color.lighten(92%),
    stroke: (left: 2.6pt + accent-color.lighten(15%)),
    radius: (right: 4pt),
    inset: (x: 1.1em, y: 0.75em),
  )[
    #set text(style: "italic", size: 0.88em, fill: _ink.lighten(12%))
    #it.body
    #if _has(it.attribution) {
      v(0.4em)
      align(right, text(style: "normal", size: 0.8em, fill: accent-color.darken(5%))[— #it.attribution])
    }
  ]

  // tables. NOTE: Pandoc emits an explicit `inset: 6pt` on every table, which
  // overrides any `set table(inset:)` here; build.sh/build.ps1 rewrite that
  // token in the generated .typ. This default still applies to raw-Typst tables.
  set table(stroke: 0.7pt + _ink.lighten(72%), inset: (x: 0.95em, y: 0.72em))
  show table.cell: it => {
    if it.y == 0 {
      set text(fill: accent-color.darken(5%), weight: "bold", size: 0.85em)
    }
    it
  }

  // ---- touying registration ----
  show: touying-slides.with(
    config-page(
      ..utils.page-args-from-aspect-ratio(aspect-ratio),
      fill: _paper,
      margin: (top: 5.5em, bottom: 1.3em, x: _page-x),
    ),
    config-common(
      slide-fn: slide,
      new-section-slide-fn: new-section-slide,
    ),
    config-methods(
      init: (self: none, body) => {
        set text(size: 20pt, lang: "ru")
        body
      },
      alert: utils.alert-with-primary-color,
    ),
    config-colors(
      primary: accent-color,
      secondary: accent-color.lighten(25%),
      neutral-lightest: _paper,
      neutral-light: _paper.darken(4%),
      neutral: _soft,
      neutral-dark: _ink.lighten(20%),
      neutral-darker: _ink,
      neutral-darkest: _ink,
    ),
    config-store(
      title: none,
      heading-fonts: heading-fonts,
      body-fonts: body-fonts,
      footer: if footer == none {
        self => if _has(self.info.title) { self.info.title } else { [] }
      } else { footer },
    ),
    ..args,
  )

  body
}
