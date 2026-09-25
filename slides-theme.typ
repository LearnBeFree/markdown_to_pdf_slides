// slides-theme.typ — minimal Touying theme for the Markdown -> Pandoc -> Typst pipeline.
// Written for Typst 0.14 / Touying 0.7.4.
//
// Slide model: slides are created by theme-filters.lua as explicit calls
// (NOT by Typst headings), so the Lua filter fully owns content grouping:
//
//   #title-slide(cover-image: none)                       — deck cover
//   #section-slide[Name]                                  — H1 divider
//   #content-slide(title: [T], section: [S],              — H2 slide ("---" in
//     body: [..], images: ((path: "..", caption: [..]),))   markdown splits it)
//
// Content placement: body text and images are tiles arranged by a
// deterministic layout engine (_tile-layout). Portrait images go to a
// full-height side column, landscape images to a bottom band. Body text
// auto-shrinks from the base size (20pt) down to _min-size (14pt); below
// that it is rendered at _min-size and allowed to overflow.

#import "@preview/touying:0.7.4": *

#let _accent-default = rgb("#8B0000")
#let _ink = rgb("#2B2723")
#let _soft = rgb("#8A8178")
#let _paper = rgb("#FDFCF9")
#let _cream = rgb("#FAF6EC")

#let _base-size = 20pt
#let _min-size = 14pt
#let _gutter = 12pt
#let _shrink-steps = range(20, 13, step: -1).map(i => i * 1pt)

#let _display-fonts = ("Oswald", "Liberation Sans", "Carlito", "FreeSans")
#let _body-fonts = ("Philosopher", "Liberation Serif", "Caladea", "FreeSerif")

#let _cstr(v) = {
  if type(v) == str { v }
  else if type(v) == content { repr(v).trim().values.at(0, default: "") }
  else { "" }
}

#let _is-empty(v) = { _cstr(v).trim() == "" }

#let _has(v) = { v != none and v != auto and not _is-empty(v) }

#let _resolve-color(v, fallback) = {
  if not _has(v) { return fallback }
  let s = _cstr(v).trim().replace("\\", "").replace("#", "").replace("\"", "").replace(" ", "").replace("'", "")
  if s.matches(regex("^[0-9a-fA-F]{6}$")).len() > 0 { return rgb("#" + s) }
  if s.matches(regex("^[0-9a-fA-F]{3}$")).len() > 0 {
    let e = s.at(0) + s.at(0) + s.at(1) + s.at(1) + s.at(2) + s.at(2)
    return rgb("#" + e)
  }
  fallback
}

#let _resolve-fonts(v, fallback) = {
  if type(v) == array { return v.map(f => _cstr(f)).filter(f => f != "") + fallback }
  if _has(v) {
    let names = _cstr(v).split(",").map(n => n.trim()).filter(n => n != "")
    if names.len() > 0 { return names + fallback }
  }
  fallback
}

#let _clean-path(v) = { _cstr(v).trim().replace("\\#", "#").replace("\\_", "_").replace("\\%", "%") }

#let _img-ar(path) = {
  let m = measure(image(path, width: 100pt))
  m.width / m.height
}

#let _shrink(self, body, width, height) = {
  let fits(s) = {
    let m = measure(block(width: width, {
      set text(size: s)
      set par(leading: 0.65em, justify: true)
      body
    }))
    m.height <= height + 0.5pt
  }
  let found = _shrink-steps.find(fits)
  let chosen = if found != none { found } else { _min-size }
  block(width: width, {
    set text(size: chosen)
    set par(leading: 0.65em, justify: true)
    body
  })
}

#let _img-tile(self, im, width, height) = {
  let path = _clean-path(im.at("path", default: ""))
  let cap = im.at("caption", default: none)
  let pic = image(path, width: 100%, height: 100%, fit: "contain")
  block(width: width, height: height, {
    if cap != none {
      grid(
        rows: (1fr, auto),
        row-gutter: 0.4em,
        align(center + horizon)[#box(width: 100%, height: 100%)[#pic]],
        align(center)[#text(size: 0.55em, fill: self.store.accent, style: "italic")[#cap]],
      )
    } else {
      box(width: 100%, height: 100%)[#pic]
    }
  })
}

#let _images-zone(self, images, width, height, stacked) = {
  let n = images.len()
  let g = _gutter / 2
  if n == 1 {
    _img-tile(self, images.at(0), width, height)
  } else if stacked {
    let rh = (height - (n - 1) * g) / n
    grid(
      rows: (rh,) * n,
      row-gutter: g,
      ..images.map(im => _img-tile(self, im, width, rh)),
    )
  } else {
    let cols = if n <= 3 { n } else { calc.ceil(calc.sqrt(n)) }
    let rows-n = calc.ceil(n / cols)
    let cw = (width - (cols - 1) * g) / cols
    let rh = (height - (rows-n - 1) * g) / rows-n
    grid(
      columns: (cw,) * cols,
      rows: (rh,) * rows-n,
      gutter: g,
      ..images.map(im => _img-tile(self, im, cw, rh)),
    )
  }
}

#let _tile-layout(self, title, body, images) = layout(size => {
  let W = size.width
  let H = size.height
  let g = _gutter
  let n = images.len()
  let has-text = body != none

  if n == 0 {
    if has-text { align(top, _shrink(self, body, W, H)) } else { [] }
  } else if n == 1 and not has-text {
    align(center + horizon, _img-tile(self, images.at(0), W, H))
  } else {
    let ars = images.map(im => _img-ar(_clean-path(im.at("path", default: ""))))
    let avg-ar = ars.fold(0.0, (acc, a) => acc + a) / ars.len()
    if avg-ar < 1.15 {
      let zw = if n == 1 { calc.min(0.46 * W, H * ars.at(0)) } else { 0.46 * W }
      let tw = W - zw - g
      grid(
        columns: (tw, zw),
        column-gutter: g,
        rows: (H,),
        align: (top + left, center + horizon),
        if has-text { _shrink(self, body, tw, H) } else { [] },
        _images-zone(self, images, zw, H, true),
      )
    } else {
      let zh = if n == 1 {
        let base-h = if has-text {
          measure(block(width: W, {
            set text(size: _base-size)
            set par(leading: 0.65em, justify: true)
            body
          })).height
        } else { 0pt }
        let room = H - base-h - g
        calc.min(calc.max(room, 0.35 * H), 0.7 * H, W / ars.at(0))
      } else { 0.5 * H }
      let th = H - zh - g
      grid(
        columns: (W,),
        rows: (th, zh),
        row-gutter: g,
        align: (top + left, center + horizon),
        if has-text { _shrink(self, body, W, th) } else { [] },
        if n == 1 { _img-tile(self, images.at(0), W, zh) } else { _images-zone(self, images, W, zh, false) },
      )
    }
  }
})

#let _header(self, title, section) = {
  set align(left + top)
  set text(font: self.store.hfonts)
  grid(
    columns: (1fr, auto),
    column-gutter: 1em,
    align: (left + bottom, right + bottom),
    if title != none {
      utils.fit-to-width(grow: false, 100%, text(size: 1.6em, fill: self.store.accent, weight: "bold", title))
    } else { [] },
    if section != none {
      text(size: 0.55em, fill: _soft, font: self.store.bfonts, section)
    } else { [] },
  )
  v(0.45em, weak: true)
  line(length: 100%, stroke: 1.3pt + self.store.accent.lighten(30%))
}

#let _footer(self) = {
  set align(bottom)
  set text(size: 0.5em, fill: _soft, font: self.store.bfonts)
  let deck = if self.store.footer != none { self.store.footer } else { self.info.title }
  pad(
    .5em,
    grid(
      columns: (1fr, auto),
      align: (left, right),
      if deck != none { deck } else { [] },
      context utils.slide-counter.display() + " / " + utils.last-slide-number,
    ),
  )
  place(bottom, components.progress-bar(height: 2.5pt, self.store.accent, self.store.accent.lighten(84%)))
}

#let content-slide(title: none, section: none, body: none, images: ()) = touying-slide-wrapper(self => {
  touying-slide(
    self: self,
    config: config-page(header: _header(self, title, section), footer: _footer(self)),
    _tile-layout(self, title, body, images),
  )
})

#let section-slide(body) = touying-slide-wrapper(self => {
  touying-slide(
    self: self,
    config: config-page(header: none, footer: _footer(self)),
    align(horizon, {
      set text(font: self.store.hfonts, fill: self.store.accent)
      set align(center)
      text(size: 1.7em, weight: "bold", body)
      v(1em)
      block(width: 100%, align(center)[#line(length: 22%, stroke: 3pt + self.store.accent)])
    }),
  )
})

#let focus-slide(body) = touying-slide-wrapper(self => {
  touying-slide(
    self: self,
    config: utils.merge-dicts(
      config-page(fill: self.store.accent, margin: 2em, header: none, footer: none),
      config-common(freeze-slide-counter: true),
    ),
    align(horizon + center, text(size: 1.5em, fill: _cream, font: self.store.hfonts, body)),
  )
})

#let title-slide(cover-image: none) = touying-slide-wrapper(self => {
  let info = self.info
  let meta-line = {
    let parts = ()
    if info.author != none { parts.push(info.author) }
    if info.date != none { parts.push(info.date) }
    if info.institution != none { parts.push(info.institution) }
    parts.join("  ·  ")
  }
  if _has(cover-image) {
    let cover = _clean-path(cover-image)
    touying-slide(
      self: self,
      config: utils.merge-dicts(
        config-page(margin: 0em, header: none, footer: none),
        config-common(freeze-slide-counter: true),
      ),
      {
        box(width: 100%, height: 100%)[#image(cover, width: 100%, height: 100%, fit: "cover")]
        place(top + center, box(width: 100%, height: 100%)[#rect(
          width: 100%,
          height: 100%,
          fill: gradient.linear(
            (rgb(0, 0, 0, 0), 0%),
            (rgb(0, 0, 0, 0), 35%),
            (rgb(0, 0, 0, 185), 100%),
            angle: 90deg,
          ),
          stroke: none,
        )])
        place(bottom + left, dx: 2em, dy: -2.2em, {
          set text(fill: _cream)
          if info.title != none { text(size: 1.6em, font: self.store.hfonts, weight: "bold", info.title) }
          if info.subtitle != none { v(0.4em); text(size: 0.9em, info.subtitle) }
          if meta-line != "" { v(0.9em); text(size: 0.65em, fill: _cream.lighten(70%), meta-line) }
        })
      },
    )
  } else {
    touying-slide(
      self: self,
      config: utils.merge-dicts(
        config-page(header: none, footer: none),
        config-common(freeze-slide-counter: true),
      ),
      align(horizon + center, {
        set align(center)
        if info.title != none {
          text(size: 1.8em, font: self.store.hfonts, weight: "bold", fill: _ink, info.title)
        }
        v(1em)
        line(length: 15%, stroke: 3pt + self.store.accent)
        if info.subtitle != none { v(0.8em); text(size: 0.95em, fill: _soft, info.subtitle) }
        if meta-line != "" { v(1.4em); text(size: 0.65em, fill: _soft, meta-line) }
      }),
    )
  }
})

#let slides-theme(
  aspect-ratio: "16-9",
  accent: auto,
  title-font: auto,
  body-font: auto,
  footer: auto,
  ..args,
  body,
) = {
  let accent = _resolve-color(accent, _accent-default)
  let hfonts = _resolve-fonts(title-font, _display-fonts)
  let bfonts = _resolve-fonts(body-font, _body-fonts)
  let footer-t = if footer != auto and footer != none { footer } else { none }

  set text(size: _base-size, font: bfonts, lang: "ru", fill: _ink)
  set par(justify: true, leading: 0.65em)
  set list(marker: text(fill: accent)[▪], indent: 0.6em, body-indent: 1em, spacing: 0.6em)
  set enum(spacing: 0.6em)
  set strong(delta: 300)
  show strong: it => text(fill: accent, it.body)
  show link: it => text(fill: accent.darken(10%), it)
  show raw.where(block: true): block.with(fill: _ink.lighten(94%), inset: 0.8em, radius: 4pt, width: 100%)
  show raw.where(block: false): box.with(fill: _ink.lighten(94%), inset: (x: 0.2em, y: 0.1em), radius: 3pt)

  show quote: it => block(
    width: 100%,
    fill: accent.lighten(93%),
    stroke: (left: 2.6pt + accent),
    radius: (right: 4pt),
    inset: (x: 1em, y: 0.75em),
  )[
    #set text(size: 0.88em, style: "italic")
    #it.body
    #if it.at("attribution", default: none) != none [
      #v(0.3em)
      #set align(right)
      #text(size: 0.8em, style: "normal", fill: _soft)[— #it.attribution]
    ]
  ]

  show table.cell.where(y: 0): set text(weight: "bold", fill: accent, size: 0.85em)
  set table(stroke: 0.7pt + _ink.lighten(72%))

  show: touying-slides.with(
    config-page(
      ..utils.page-args-from-aspect-ratio(aspect-ratio),
      fill: _paper,
      margin: (top: 4.4em, bottom: 1.6em, x: 2em),
    ),
    config-colors(primary: accent),
    config-store(accent: accent, hfonts: hfonts, bfonts: bfonts, footer: footer-t),
    ..args,
  )

  body
}
