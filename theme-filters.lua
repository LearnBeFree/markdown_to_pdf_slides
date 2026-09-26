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
--   ```{=typst} raw block -> flushed verbatim at top level (power-user
--              escape hatch: it is compiled as-is, so invalid Typst inside
--              aborts the build with an error pointing at that block)
--
-- Everything else (paragraphs, lists, tables, quotes, inline images) becomes
-- slide body text. Missing/unreadable images degrade to a dashed placeholder
-- box plus a stderr warning instead of a compile error. Image paths are
-- resolved to ABSOLUTE filesystem paths (relative to the source .md, its
-- percent-decoded form, or the working directory), so the generated .typ can
-- live anywhere as long as typst runs with `--root /` (see build.sh).

local function esc_str(s)
  return (s:gsub('[\\"]', '\\%0'))
end

-- Metadata value that the typst writer must emit VERBATIM (file paths:
-- template interpolation escapes characters like `_`, which corrupts them).
local function meta_raw_typst(s)
  return pandoc.MetaInlines({ pandoc.RawInline("typst", s) })
end

local function percent_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function input_dir()
  local base = PANDOC_STATE.input_files[1]
  if base then
    local dir = base:match("^(.*)[/\\]")
    if dir and dir ~= "" then return dir end
  end
  return "."
end

-- True only for readable non-empty regular files: io.open also succeeds on
-- directories (Linux), and a 0-byte file would crash typst's image decoder.
local function sniff_image(f)
  -- typst picks its decoder by file EXTENSION, so a wrong or unknown format
  -- would abort the whole build; sniff magic bytes instead and degrade.
  f:seek("set")
  local head = f:read(16) or ""
  if head:sub(1, 3) == "\255\216\255" then return "jpg" end
  if head:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
  if head:sub(1, 6) == "GIF87a" or head:sub(1, 6) == "GIF89a" then return "gif" end
  if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WEBP" then return "webp" end
  if head:match("^%s*<%?xml") or head:match("^%s*<svg") then return "svg" end
  return nil
end

local function is_abs(p)
  return p:sub(1, 1) == "/" or p:sub(1, 1) == "\\" or p:match("^[A-Za-z]:[/\\]") ~= nil
end

-- Resolve an image reference to an absolute, forward-slashed path that typst
-- can load. Returns nil + reason when nothing matches, the file is not an
-- image, or its extension does not fit the actual content.
local function resolve_media(src)
  if not src or src == "" then return nil, "empty path" end
  local dir = input_dir()
  local cwd = pandoc.system.get_working_directory()
  local cands = {}
  local variants = { src }
  local dec = percent_decode(src)
  if dec ~= src then variants[#variants + 1] = dec end
  for _, v in ipairs(variants) do
    if is_abs(v) then
      cands[#cands + 1] = v
    else
      cands[#cands + 1] = dir .. "/" .. v
      cands[#cands + 1] = cwd .. "/" .. v
    end
  end
  for _, p in ipairs(cands) do
    local f = io.open(p, "rb")
    if f then
      local ok, size = pcall(function() return f:seek("end") end)
      if ok and size ~= nil and size > 0 then
        local kind = sniff_image(f)
        f:close()
        if kind == nil then
          return nil, "not an image (supported: png, jpg/jpeg, gif, webp, svg): " .. p
        end
        local e = (p:match("%.(%w+)%s*$") or ""):lower()
        local ext_ok = e == kind or (kind == "jpg" and e == "jpeg")
        if not ext_ok then
          return nil, "extension ." .. e .. " does not match detected " .. kind
            .. " content (typst decodes by extension): " .. p
        end
        return (p:gsub("\\", "/"))
      end
      f:close()
    end
  end
  return nil, "not found"
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
  local p, err = resolve_media(img.src or "")
  if not p then
    io.stderr:write("WARNING: skipping image ", img.src or "", " (", err, ")\n")
    return pandoc.RawInline("typst", placeholder_box("нет изображения: " .. (img.src or "")))
  end
  return pandoc.RawInline("typst", '#image("' .. esc_str(p) .. '")')
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

  local cover = meta["cover-image"]
  if cover then
    local p = pandoc.utils.stringify(cover)
    local r, err = resolve_media(p)
    if p ~= "" and not r then
      io.stderr:write("WARNING: cover-image ", err, " — using light title slide\n")
      meta["cover-image"] = nil
    elseif r then
      -- absolute path so the cover also loads when the .typ lives elsewhere
      meta["cover-image"] = meta_raw_typst(esc_str(r))
    end
  end

  -- build.sh/ps1 export THEME_DIR so the template can import slides-theme.typ
  -- by absolute path (the generated .typ may live next to the source .md).
  if not meta["theme-dir"] then
    local tdir = os.getenv("THEME_DIR")
    if tdir and tdir ~= "" then
      meta["theme-dir"] = meta_raw_typst(esc_str((tdir:gsub("\\", "/"))))
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
          local p, err = resolve_media(tile.path)
          if p then
            images[#images + 1] = { path = p, caption = tile.caption }
          else
            io.stderr:write("WARNING: skipping image ", tile.path, " (", err, ")\n")
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
