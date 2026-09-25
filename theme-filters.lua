-- theme-filters.lua — Pandoc AST -> Typst slide calls for slides-theme.typ.
--
-- Markdown semantics (the user controls slide breaks):
--   #  H1   -> #section-slide[Name]                       (divider slide)
--   ## H2  -> #content-slide(title: [...], ...)           (new slide)
--   ---    -> split: a new #content-slide with the SAME   (no marker)
--              title and section as the current one
--   ### H3+ -> bold paragraph inside the current slide
--   ![cap](img) as a standalone paragraph -> image "tile":
--              passed via images: (...) to the layout engine
--   ```{=typst} raw block -> flushed verbatim at top level (power-user escape)
--
-- Everything else (paragraphs, lists, tables, quotes, inline images) becomes
-- slide body text. Missing image files degrade to a dashed placeholder box
-- plus a stderr warning instead of a compile error.

local function esc_str(s)
  return (s:gsub('[\\"]', '\\%0'))
end

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r")
  if f then f:close() return true end
  local base = PANDOC_STATE.input_files[1]
  if base then
    local dir = base:match("^(.*)[/\\]") or "."
    local f2 = io.open(dir .. "/" .. path, "r")
    if f2 then f2:close() return true end
  end
  return false
end

local function placeholder_box(label)
  return '#box(width: 100%, height: 110pt, stroke: (paint: rgb("#9A9186"), '
    .. 'thickness: 0.8pt, dash: "dashed"), radius: 4pt)'
    .. '[#align(center + horizon)[#text(fill: rgb("#9A9186"), size: 0.8em)['
    .. esc_str(label) .. ']]]'
end

local function image_to_raw(img)
  local src = img.src or ""
  if not file_exists(src) then
    io.stderr:write("WARNING: image not found: ", src, "\n")
    return pandoc.RawInline("typst", placeholder_box("нет изображения: " .. src))
  end
  return pandoc.RawInline("typst", '#image("' .. esc_str(src) .. '")')
end

local function write_block(b)
  local walked = pandoc.walk_block(b, { Image = image_to_raw })
  return pandoc.write(pandoc.Pandoc({ walked }), "typst")
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

  local cover = meta["cover-image"]
  if cover then
    local p = pandoc.utils.stringify(cover)
    if p ~= "" and not file_exists(p) then
      io.stderr:write("WARNING: cover-image not found, using light title slide: ", p, "\n")
      meta["cover-image"] = nil
    end
  end

  local out = {}
  local section, title = nil, nil
  local body_blocks, images = {}, {}
  local emitted_for_title = false
  local toc_entries = {}

  -- Frontmatter flag: `toc: false` hides the outline slide that otherwise
  -- follows the deck title. Anything else (or absent) keeps it visible.
  local show_toc = true
  local tocv = meta["toc"]
  if tocv ~= nil then
    local v = pandoc.utils.stringify(tocv)
    if v == "false" or v == "no" or v == "off" then show_toc = false end
  end

  local function emit_content(include_images)
    local chunks = { "#content-slide(" }
    if title ~= nil then chunks[#chunks + 1] = "  title: [" .. title .. "]," end
    if section ~= nil then chunks[#chunks + 1] = "  section: [" .. section .. "]," end
    if include_images and #images > 0 then
      local ims = {}
      for _, im in ipairs(images) do
        local d = '(path: "' .. esc_str(im.path) .. '"'
        if im.caption then d = d .. ", caption: [" .. im.caption .. "]" end
        ims[#ims + 1] = d .. "), "
      end
      chunks[#chunks + 1] = "  images: (" .. table.concat(ims) .. "),"
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
      local d = '(path: "' .. esc_str(im.path) .. '"'
      if im.caption then d = d .. ", caption: [" .. im.caption .. "]" end
      ims[#ims + 1] = d .. "), "
    end
    out[#out + 1] = "#gallery-slide(\n  (" .. table.concat(ims) .. "),\n)"
  end

  local function flush(force)
    local has_content = #body_blocks > 0 or #images > 0
    if not has_content and not (force and title ~= nil and not emitted_for_title) then
      body_blocks, images = {}, {}
      return
    end
    if title == nil and not has_content then
      body_blocks, images = {}, {}
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
        local name = ser_inlines(b.content)
        out[#out + 1] = "#section-slide[" .. name .. "]"
        toc_entries[#toc_entries + 1] = { level = 1, text = name }
        section, title = name, nil
      elseif b.level == 2 then
        flush(true)
        title = ser_inlines(b.content)
        toc_entries[#toc_entries + 1] = { level = 2, text = title }
        emitted_for_title = false
      else
        body_blocks[#body_blocks + 1] = pandoc.Para(pandoc.Strong(b.content))
      end
    elseif b.t == "HorizontalRule" then
      flush(false)
    elseif b.t == "RawBlock" and b.format == "typst" then
      flush(false)
      out[#out + 1] = b.text
      -- the raw block acts as this slide's content: don't emit a phantom
      -- title-only slide for it afterwards
      if title ~= nil then emitted_for_title = true end
    else
      local tiles = as_image_tiles(b)
      if #tiles > 0 then
        for _, tile in ipairs(tiles) do
          if file_exists(tile.path) then
            images[#images + 1] = tile
          else
            io.stderr:write("WARNING: image not found: ", tile.path, "\n")
            body_blocks[#body_blocks + 1] =
              pandoc.Plain(pandoc.RawInline("typst", placeholder_box("нет изображения: " .. tile.path)))
          end
        end
      else
        body_blocks[#body_blocks + 1] = b
      end
    end
  end
  flush(true)

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
