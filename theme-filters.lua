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

-- A standalone image block: a Figure wrapping a single Image, or a
-- Para/Plain whose only inline is an Image.
local function as_image_tile(b)
  local img, caption
  if b.t == "Figure" then
    local inl = {}
    for _, blk in ipairs(b.content) do
      if blk.t == "Para" or blk.t == "Plain" then
        for _, i in ipairs(blk.content) do inl[#inl + 1] = i end
      end
    end
    local imgs = {}
    for _, i in ipairs(inl) do if i.t == "Image" then imgs[#imgs + 1] = i end end
    if #inl == 1 and #imgs == 1 then
      img = imgs[1]
      local cap = b.caption
      if cap ~= nil and cap.long ~= nil then cap = cap.long end
      if cap ~= nil and #cap > 0 then caption = ser_blocks_list(cap) end
    end
  elseif b.t == "Para" or b.t == "Plain" then
    if #b.content == 1 and b.content[1].t == "Image" then
      img = b.content[1]
      if img.caption and #img.caption > 0 then
        caption = pandoc.write(pandoc.Pandoc({ pandoc.Plain(img.caption) }), "typst")
      end
    end
  end
  if img == nil then return nil end
  return { path = img.src or "", caption = (caption and caption ~= "") and caption or nil }
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

  local function flush(force)
    local has_content = #body_blocks > 0 or #images > 0
    if not has_content and not (force and title ~= nil) then
      body_blocks, images = {}, {}
      return
    end
    if title == nil and not has_content then
      body_blocks, images = {}, {}
      return
    end
    local chunks = { "#content-slide(" }
    if title ~= nil then chunks[#chunks + 1] = "  title: [" .. title .. "]," end
    if section ~= nil then chunks[#chunks + 1] = "  section: [" .. section .. "]," end
    if #images > 0 then
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
    body_blocks, images = {}, {}
  end

  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" then
      if b.level == 1 then
        flush(true)
        local name = ser_inlines(b.content)
        out[#out + 1] = "#section-slide[" .. name .. "]"
        section, title = name, nil
      elseif b.level == 2 then
        flush(true)
        title = ser_inlines(b.content)
      else
        body_blocks[#body_blocks + 1] = pandoc.Para(pandoc.Strong(b.content))
      end
    elseif b.t == "HorizontalRule" then
      flush(false)
    elseif b.t == "RawBlock" and b.format == "typst" then
      flush(false)
      out[#out + 1] = b.text
    else
      local tile = as_image_tile(b)
      if tile ~= nil then
        if file_exists(tile.path) then
          images[#images + 1] = tile
        else
          io.stderr:write("WARNING: image not found: ", tile.path, "\n")
          body_blocks[#body_blocks + 1] =
            pandoc.Plain(pandoc.RawInline("typst", placeholder_box("нет изображения: " .. tile.path)))
        end
      else
        body_blocks[#body_blocks + 1] = b
      end
    end
  end
  flush(true)

  return pandoc.Pandoc({ pandoc.RawBlock("typst", table.concat(out, "\n\n")) }, meta)
end
