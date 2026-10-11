-- theme-filters.lua — Pandoc AST -> Typst slide calls for slides-theme.typ.
--
-- Markdown semantics (the user controls slide breaks):
--   #  H1   -> #section-slide[Name]                       (divider slide;
--              image paragraphs directly under the H1 become its
--              full-bleed background, like the title-slide cover)
--   ## H2  -> #content-slide(title: [...], ...)           (new slide)
--              ...UNLESS the slide has no text: an empty H2 becomes a
--              #focus-slide[Title] (statement slide), and an H2 followed
--              only by images becomes a focus slide with a background
--   ---    -> split: a new #content-slide with the SAME   (no marker)
--              title and section as the current one
--   ### H3+ -> bold paragraph inside the current slide
--   ![cap](img) as a standalone paragraph -> image "tile":
--              passed via images: (...) to the layout engine
--   ```{=typst} raw block -> flushed verbatim at top level (power-user
--              escape hatch: it is compiled as-is, so invalid Typst inside
--              aborts the build with an error pointing at that block)
--
-- Everything else (paragraphs, lists, tables, quotes, inline images) becomes
-- slide body text.
--
-- IMAGES: this filter does NO filesystem I/O. build.sh probes the AST
-- (image-probe.lua), resolves every reference with bash (Unicode-safe on
-- Windows, unlike Lua io.open), sniffs the real format from magic bytes and
-- delivers the results via --metadata argv (the one Unicode-safe channel
-- into native pandoc):
--   image-map:      records "src \30 typst-path \30 format" joined with \31
--   missing-images: records "src \30 reason" joined with \31
-- (Lua escapes are DECIMAL: \30 = record separator, \31 = unit separator —
-- matching bash's octal $'\036' / $'\037'. Control characters cannot occur
-- in filenames, so the encoding is unambiguous.) Missing/unreadable images degrade to a dashed placeholder
-- box plus a stderr warning instead of a compile error; the explicit
-- `format:` argument makes extensions (missing or lying) irrelevant.

local function esc_str(s)
  return (s:gsub('[\\"]', '\\%0'))
end

-- Metadata value that the typst writer must emit VERBATIM (file paths:
-- template interpolation escapes characters like `_`, which corrupts them).
local function meta_raw_typst(s)
  return pandoc.MetaInlines({ pandoc.RawInline("typst", s) })
end

local IMAGE_MAP = {}   -- src -> { path = "...", format = "png|jpg|..." }
local IMAGE_MISS = {}  -- src -> reason string

local function split_records(joined, fn)
  for rec in joined:gmatch("[^\31]+") do
    local a, b, c = rec:match("^([^\30]*)\30([^\30]*)\30?([^\30]*)")
    fn(a, b, c)
  end
end

-- must run BEFORE any image lookup (feeds the map from build.sh's probe)
local function ingest_manifest(meta)
  local m = meta["image-map"]
  if m then
    split_records(pandoc.utils.stringify(m), function(src, path, fmt)
      if src ~= "" and path ~= "" then
        IMAGE_MAP[src] = { path = path, format = (fmt ~= "" and fmt or nil) }
      end
    end)
    meta["image-map"] = nil
  end
  m = meta["missing-images"]
  if m then
    split_records(pandoc.utils.stringify(m), function(src, why)
      if src ~= "" then IMAGE_MISS[src] = (why ~= "" and why or "не найден") end
    end)
    meta["missing-images"] = nil
  end
end

local function lookup_image(src)
  if not src or src == "" then return nil, "пустой путь" end
  local hit = IMAGE_MAP[src]
  if hit then return hit end
  return nil, IMAGE_MISS[src] or "не найден"
end

local function image_code(hit)
  local f = hit.format and (', format: "' .. hit.format .. '"') or ""
  return '#image("' .. esc_str(hit.path) .. '"' .. f .. ')'
end

local function placeholder_box(label)
  -- The label is injected as a Typst STRING (not markup), so characters like
  -- # $ [ ] in filenames cannot break parsing.
  return '#box(width: 100%, height: 110pt, stroke: (paint: rgb("#9A9186"), '
    .. 'thickness: 0.8pt, dash: "dashed"), radius: 4pt)'
    .. '[#align(center + horizon)[#text(fill: rgb("#9A9186"), size: 0.8em)['
    .. '#("' .. esc_str(label) .. '")'
    .. ']]]'
end

local function image_to_raw(img)
  local hit, why = lookup_image(img.src or "")
  if not hit then
    io.stderr:write("slides: ВНИМАНИЕ: картинка ", img.src or "",
      " — ", why, " — поставлена заглушка\n")
    return pandoc.RawInline("typst",
      placeholder_box("нет изображения: " .. (img.src or "")))
  end
  return pandoc.RawInline("typst", image_code(hit))
end

local function write_block(b)
  local walked = pandoc.walk_block(b, { Image = image_to_raw })
  local s = pandoc.write(pandoc.Pandoc({ walked }), "typst")
  -- Pandoc hardcodes a cramped `inset: <n>pt` on every table; widen the cell
  -- padding here, scoped to writer output only (a sed over the whole file
  -- would also mangle user ```{=typst}``` blocks).
  return (s:gsub("inset: [0-9.]+pt", "inset: (x: 0.95em, y: 0.72em)"))
end

local function ser_inlines(inlines)
  local walked = pandoc.walk_block(pandoc.Plain(inlines), { Image = image_to_raw })
  return pandoc.write(pandoc.Pandoc({ walked }), "typst")
end

local function ser_blocks_list(blocks)
  local parts = {}
  for _, b in ipairs(blocks) do parts[#parts + 1] = write_block(b) end
  return table.concat(parts, "\n\n")
end

-- Standalone image blocks: a Figure, or a Para/Plain consisting ONLY of
-- images (one or several, possibly separated by line breaks). Each becomes
-- an image tile; captions come from the Figure caption or the image alt text.
local function ignorable_inline(i)
  return i.t == "Space" or i.t == "SoftBreak"
end

local function as_image_tiles(b)
  local tiles = {}
  if b.t == "Figure" then
    local inl, imgs = {}, {}
    for _, blk in ipairs(b.content) do
      if blk.t == "Para" or blk.t == "Plain" then
        for _, i in ipairs(blk.content) do inl[#inl + 1] = i end
      end
    end
    local only = true
    for _, i in ipairs(inl) do
      if i.t == "Image" then imgs[#imgs + 1] = i
      elseif not ignorable_inline(i) then only = false end
    end
    if only and #imgs > 0 then
      local cap
      local capb = b.caption
      if capb ~= nil and capb.long ~= nil then capb = capb.long end
      if capb ~= nil and #capb > 0 then cap = ser_blocks_list(capb) end
      for k, img in ipairs(imgs) do
        tiles[#tiles + 1] = { path = img.src or "", caption = (k == 1) and cap or nil }
      end
    end
  elseif b.t == "Para" or b.t == "Plain" then
    local imgs = {}
    local only = true
    for _, i in ipairs(b.content) do
      if i.t == "Image" then imgs[#imgs + 1] = i
      elseif not ignorable_inline(i) then only = false end
    end
    if only and #imgs > 0 then
      for _, img in ipairs(imgs) do
        local cap
        if img.caption and #img.caption > 0 then
          cap = pandoc.write(pandoc.Pandoc({ pandoc.Plain(img.caption) }), "typst")
        end
        tiles[#tiles + 1] = { path = img.src or "", caption = (cap ~= "" ) and cap or nil }
      end
    end
  end
  return tiles
end

function Pandoc(doc)

  local meta = doc.meta
  ingest_manifest(meta)

  local cover = meta["cover-image"]
  if cover then
    local src = pandoc.utils.stringify(cover)
    if src == "" then
      meta["cover-image"] = nil
    else
      local hit, why = lookup_image(src)
      if not hit then
        io.stderr:write("slides: ВНИМАНИЕ: cover-image ", src,
          " — ", why, " — титульный слайд без обложки\n")
        meta["cover-image"] = nil
      else
        -- absolute typst-virtual path so the cover also loads when the .typ
        -- lives elsewhere; format travels in cover-format (see template.typ)
        meta["cover-image"] = meta_raw_typst(esc_str(hit.path))
        if hit.format then meta["cover-format"] = meta_raw_typst(hit.format) end
      end
    end
  end

  local out = {}
  local section, title = nil, nil
  local body_blocks, images = {}, {}
  local emitted_for_title = false
  local toc_entries = {}

  -- Pending H1 divider: emitted only once we know whether images follow it
  -- directly (they become the divider background). `after_h1` is true while
  -- only image-only paragraphs have been seen since the H1.
  local pending_section = nil
  local after_h1 = false

  -- Frontmatter flag: `toc: false` hides the outline slide that otherwise
  -- follows the deck title. Anything else (or absent) keeps it visible.
  local show_toc = true
  local tocv = meta["toc"]
  if tocv ~= nil then
    local v = pandoc.utils.stringify(tocv)
    if v == "false" or v == "no" or v == "off" then show_toc = false end
  end

  local function image_dict(im)
    local hit, why = lookup_image(im.path)
    if not hit then return nil, why end
    local d = '(path: "' .. esc_str(hit.path) .. '"'
      .. ', format: "' .. (hit.format or "") .. '"'
    if im.caption then d = d .. ", caption: [" .. im.caption .. "]" end
    return d .. "), "
  end

  -- named args for statement-slide backgrounds; typst call syntax puts
  -- args before the content block: #section-slide(args)[Name]
  local function bg_args(path)
    local hit, why = lookup_image(path)
    if not hit then return nil, why end
    local args = 'background-image: "' .. esc_str(hit.path) .. '"'
    if hit.format then
      args = args .. ', background-format: "' .. hit.format .. '"'
    end
    return args
  end

  local function emit_content(include_images)
    local chunks = { "#content-slide(" }
    if title ~= nil then chunks[#chunks + 1] = "  title: [" .. title .. "]," end
    if section ~= nil then chunks[#chunks + 1] = "  section: [" .. section .. "]," end
    if include_images and #images > 0 then
      local ims = {}
      for _, im in ipairs(images) do
        local d = image_dict(im)
        if d then ims[#ims + 1] = d end
      end
      if #ims > 0 then chunks[#chunks + 1] = "  images: (" .. table.concat(ims) .. ")," end
    end
    if #body_blocks > 0 then
      chunks[#chunks + 1] = "  body: [\n" .. ser_blocks_list(body_blocks) .. "\n  ],"
    end
    chunks[#chunks + 1] = ")"
    out[#out + 1] = table.concat(chunks, "\n")
  end

  local function emit_gallery()
    local ims = {}
    for _, im in ipairs(images) do
      local d = image_dict(im)
      if d then ims[#ims + 1] = d end
    end
    out[#out + 1] = "#gallery-slide(\n  (" .. table.concat(ims) .. "),\n)"
  end

  -- Statement slide: big text on an accent (or background-image) slide.
  local function emit_focus(bg_path)
    if bg_path then
      local a, why = bg_args(bg_path)
      if a then
        out[#out + 1] = "#focus-slide(" .. a .. ")[" .. title .. "]"
        return
      end
      io.stderr:write("slides: ВНИМАНИЕ: картинка ", bg_path,
        " — ", why, " — фон слайда не установлен\n")
    end
    out[#out + 1] = "#focus-slide[" .. title .. "]"
  end

  -- The pending H1 divider: emitted deferred, once we know whether image
  -- paragraphs follow it directly (they become its background).
  local function finalize_section()
    if not pending_section then return end
    local a
    if pending_section.bg then
      a = bg_args(pending_section.bg)
      if not a then
        local _, why = lookup_image(pending_section.bg)
        io.stderr:write("slides: ВНИМАНИЕ: картинка ", pending_section.bg,
          " — ", why, " — фон разделителя не установлен\n")
      end
    end
    if a then
      out[#out + 1] = "#section-slide(" .. a .. ")[" .. pending_section.name .. "]"
    else
      out[#out + 1] = "#section-slide[" .. pending_section.name .. "]"
    end
    toc_entries[#toc_entries + 1] = { level = 1, text = pending_section.name }
    if #pending_section.extra > 0 then
      local ims = {}
      for _, im in ipairs(pending_section.extra) do
        local d = image_dict(im)
        if d then ims[#ims + 1] = d end
      end
      if #ims > 0 then
        out[#out + 1] = "#gallery-slide(\n  (" .. table.concat(ims) .. "),\n)"
      end
    end
    pending_section = nil
  end

  local function flush(force)
    local has_content = #body_blocks > 0 or #images > 0
    if not has_content and not (force and title ~= nil and not emitted_for_title) then
      body_blocks, images = {}, {}
      return
    end
    -- Statement slide: an H2 whose slide has no text (nothing at all, or
    -- images only) becomes a focus slide; a lone image is its background.
    if title ~= nil and not emitted_for_title and #body_blocks == 0 then
      local bg = nil
      if #images >= 1 then bg = table.remove(images, 1) end
      emit_focus(bg and bg.path or nil)
      if #images > 0 then emit_gallery() end
      body_blocks, images = {}, {}
      emitted_for_title = true
      return
    end
    if #images >= 2 then
      -- Image-only mode: >=2 images move to a clean gallery slide;
      -- accompanying text (if any) goes to a separate titled slide first.
      if #body_blocks > 0 then emit_content(false) end
      emit_gallery()
    else
      emit_content(true)
    end
    body_blocks, images = {}, {}
    if title ~= nil then emitted_for_title = true end
  end

  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" then
      if b.level == 1 then
        flush(true)
        finalize_section()
        local name = ser_inlines(b.content)
        pending_section = { name = name, bg = nil, extra = {} }
        after_h1 = true
        section, title = name, nil
      elseif b.level == 2 then
        flush(true)
        finalize_section()
        after_h1 = false
        title = ser_inlines(b.content)
        toc_entries[#toc_entries + 1] = { level = 2, text = title }
        emitted_for_title = false
      else
        after_h1 = false
        body_blocks[#body_blocks + 1] = pandoc.Para(pandoc.Strong(b.content))
      end
    elseif b.t == "HorizontalRule" then
      if after_h1 then finalize_section(); after_h1 = false end
      flush(false)
    elseif b.t == "RawBlock" and b.format == "typst" then
      if after_h1 then finalize_section(); after_h1 = false end
      flush(false)
      out[#out + 1] = b.text
      -- the raw block acts as this slide's content: don't emit a phantom
      -- title-only slide for it afterwards
      if title ~= nil then emitted_for_title = true end
    else
      local tiles = as_image_tiles(b)
      if #tiles > 0 and after_h1 then
        -- image paragraphs directly under the H1: divider background(s)
        for _, tile in ipairs(tiles) do
          local hit, why = lookup_image(tile.path)
          if hit then
            if not pending_section.bg then
              pending_section.bg = tile.path
            else
              pending_section.extra[#pending_section.extra + 1] = tile
            end
          else
            io.stderr:write("slides: ВНИМАНИЕ: картинка ", tile.path,
              " — ", why, " — фон разделителя не установлен\n")
          end
        end
      elseif #tiles > 0 then
        for _, tile in ipairs(tiles) do
          local hit, why = lookup_image(tile.path)
          if hit then
            images[#images + 1] = { path = tile.path, caption = tile.caption }
          else
            io.stderr:write("slides: ВНИМАНИЕ: картинка ", tile.path,
              " — ", why, " — поставлена заглушка\n")
            body_blocks[#body_blocks + 1] =
              pandoc.Plain(pandoc.RawInline("typst",
                placeholder_box("нет изображения: " .. tile.path)))
          end
        end
      else
        if after_h1 then finalize_section(); after_h1 = false end
        body_blocks[#body_blocks + 1] = b
      end
    end
  end
  flush(true)
  finalize_section()

  if show_toc and #toc_entries > 0 then
    local es = {}
    for _, e in ipairs(toc_entries) do
      es[#es + 1] = "(level: " .. e.level .. ", text: [" .. e.text .. "]), "
    end
    local pre = "#let _toc-entries = (" .. table.concat(es) .. ")\n#toc-slide(_toc-entries)"
    table.insert(out, 1, pre)
  end

  return pandoc.Pandoc({ pandoc.RawBlock("typst", table.concat(out, "\n\n")) }, meta)
end
