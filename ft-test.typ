#import "@preview/touying:0.7.4": *
#show: touying-slides.with(config-page(margin: (top: 5.2em, bottom: 1.6em, x: 2.5em), footer: {
  set text(size: 0.5em, fill: luma(60))
  place(bottom, pad(
    x: 2.9em,
    bottom: 25pt,
    {
      grid(columns: (1fr, auto), align: (left, right), [Готическая архитектура], [1 / 12])
      v(2pt)
      grid(columns: (16%, 1fr), rows: 2.5pt, gutter: 0pt, inset: 0pt, rect(fill: luma(30), width: 100%, height: 100%), rect(fill: luma(220), width: 100%, height: 100%))
    },
  ))
}))
= X
