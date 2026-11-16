// document.typ -- the layout of a PDF Tun makes (spec/pdf.md 3).
//
// Tun writes the document as data.json beside this file and runs Typst on
// it.  Every text in the data is shown as text: a string placed in content
// is never read as Typst markup or code, so nothing a person typed can
// change the layout, read a file or run anything.  This file is Tun's own
// and is the only code Typst runs.

#let data = json("data.json")

#let fonts = ("Liberation Sans", "DejaVu Sans")
#let rule = 0.8pt + luma(60)
#let hairline = 0.4pt + luma(200)

// The text settings an element's style asks for, applied to BODY.
#let styled(node, body) = {
  let style = node.at("style", default: (:))
  let settings = (:)
  if "size" in style { settings.insert("size", style.size * 1pt) }
  if "weight" in style { settings.insert("weight", style.weight) }
  if style.at("italic", default: false) { settings.insert("style", "italic") }
  if "color" in style { settings.insert("fill", rgb(style.color)) }
  if settings.len() == 0 { body } else { text(..settings, body) }
}

#let alignment(node) = {
  let align = node.at("style", default: (:)).at("align", default: "left")
  if align == "right" { right } else if align == "center" { center } else { left }
}

#let vertical(node) = {
  let align = node.at("style", default: (:)).at("valign", default: "top")
  if align == "middle" { horizon } else if align == "bottom" { bottom } else { top }
}

#let cell(node, render) = {
  let body = node.at("c", default: ()).map(render).join()
  let body = if node.tag == "th" { strong(body) } else { body }
  let style = node.at("style", default: (:))
  table.cell(colspan: node.at("colspan", default: 1), rowspan: node.at("rowspan", default: 1),
             align: alignment(node) + vertical(node), breakable: false,
             fill: if "fill" in style { rgb(style.fill) } else { none },
             styled(node, body))
}

#let rows(list, line, render) = {
  let cells = ()
  for row in list {
    cells += row.map(node => cell(node, render))
    if line != none { cells.push(table.hline(stroke: line)) }
  }
  cells
}

#let render-table(node, render) = {
  let ruled = node.head.len() > 0
  let columns = node.widths.map(width =>
    if width.at("fr", default: none) != none { width.fr * 1fr }
    else if width.at("pct", default: none) != none { width.pct * 1% }
    else if width.at("pt", default: none) != none { width.pt * 1pt }
    else { auto })
  let parts = ()
  if node.head.len() > 0 {
    parts.push(table.header(repeat: true, ..rows(node.head, none, render), table.hline(stroke: rule)))
  }
  parts += rows(node.body, if ruled { hairline } else { none }, render)
  if node.foot.len() > 0 {
    parts.push(table.footer(repeat: false, table.hline(stroke: rule), ..rows(node.foot, none, render)))
  }
  block(width: 100%, above: 1em, below: 1em, {
    if node.caption.len() > 0 {
      block(below: 0.6em, strong(node.caption.map(render).join()))
    }
    // The outer columns have no padding outside, so the table's text lines
    // up with the text above and below it.
    let last = columns.len() - 1
    table(columns: columns, stroke: none, ..parts,
          inset: (x, y) => (left: if x == 0 { 0pt } else { 4pt },
                            right: if x == last { 0pt } else { 4pt },
                            y: 4.5pt))
  })
}

#let render(node) = {
  if type(node) == str {
    node
  } else if type(node) == array {
    node.map(render).join()
  } else {
    let tag = node.tag
    let body = node.at("c", default: ()).map(render).join()
    if tag == "p" or tag == "div" {
      block(width: 100%, above: 0.9em, below: 0.9em,
            align(alignment(node), styled(node, body)))
    } else if tag == "h1" or tag == "h2" or tag == "h3" {
      let size = if tag == "h1" { 18pt } else if tag == "h2" { 14pt } else { 12pt }
      block(width: 100%, above: 1.4em, below: 0.8em, sticky: true,
            align(alignment(node),
                  heading(level: int(tag.at(1)), outlined: true, bookmarked: true,
                          text(size: size, weight: "bold", styled(node, body)))))
    } else if tag == "span" {
      styled(node, body)
    } else if tag == "strong" {
      strong(styled(node, body))
    } else if tag == "em" {
      emph(styled(node, body))
    } else if tag == "br" {
      linebreak()
    } else if tag == "hr" {
      block(above: 1.2em, below: 1.2em, line(length: 100%, stroke: hairline))
    } else if tag == "a" {
      link(node.href, text(fill: rgb("#1d4ed8"), styled(node, body)))
    } else if tag == "ul" {
      list(..node.c.map(render))
    } else if tag == "ol" {
      enum(..node.c.map(render))
    } else if tag == "li" {
      styled(node, body)
    } else if tag == "table" {
      render-table(node, render)
    } else {
      body
    }
  }
}

#let page-label = context {
  let label = data.page_label
  if label != none {
    let number = counter(page).get().first()
    let total = counter(page).final().first()
    label.replace("{pages}", str(total)).replace("{page}", str(number))
  }
}

#set document(title: data.title)
#set text(font: fonts, size: 10pt, lang: data.lang, fallback: true)
#set par(leading: 0.55em, spacing: 0.9em)
#show heading: set block(above: 0pt, below: 0pt)
#set page(
  paper: data.paper,
  margin: (top: data.margin.top * 1mm, right: data.margin.right * 1mm,
           bottom: data.margin.bottom * 1mm, left: data.margin.left * 1mm),
  header: if data.header.len() > 0 {
    text(size: 8.5pt, fill: luma(80), render(data.header))
  },
  footer: text(size: 8.5pt, fill: luma(80),
               grid(columns: (1fr, auto), column-gutter: 12pt,
                    render(data.footer), page-label)),
)

#render(data.body)
