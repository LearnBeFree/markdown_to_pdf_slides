-- theme-filters.lua — Pandoc Lua filter for the art-theme pipeline.
--
-- 1. Validates `cover-image`: if the file does not exist, the variable is
--    removed so the Typst template falls back to a clean light title slide
--    (Typst's image() would otherwise hard-crash on a missing file).
-- 2. Converts `::: {.columns}` / `::: {.column width="..."}` divs into
--    `#two-columns(columns: (...))[...][...]` raw Typst (Pandoc's Typst
--    writer drops div classes, so a filter is required).
-- 3. Converts a `## Задание` slide into a two-column
--    `#assignment[text][images]` layout (text left, images right).
-- 4. Replaces every Image with a bare `image("path")` raw Typst call so that
--    Pandoc's writer does NOT wrap it in an intrinsic-size `box(width: Npt)`
--    (which overflows the slide). Sizing is then handled by the theme.

local function esc_typst_str(s)
  return (tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'))
end

local function path_exists(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end

local function file_exists(p)
  if p == nil or p == "" then return false end
  if path_exists(p) then return true end
  local state = PANDOC_STATE
  if state and state.input_files and state.input_files[1] then
    local dir = pandoc.path.directory(state.input_files[1])
    if dir and dir ~= "" then
      if path_exists(pandoc.path.join({ dir, p })) then return true end
    end
  end
  return false
end

-- Convert a Pandoc dimension attribute to a Typst length.
-- "50%" -> 50%, "100px" -> 75pt, "3cm" -> 3cm, junk -> nil
local function conv_dim(v)
  if v == nil then return nil end
  v = tostring(v):match('^%s*(.-)%s*$')
  if v == '' then return nil end
  if v:match('^%d*%.?%d+%%$') then return v end
  local num, unit = v:match('^(%d*%.?%d+)(%a*)$')
  if num then
    unit = (unit == '' or unit == nil) and 'px' or unit
    if unit == 'px' then return string.format('%gpt', tonumber(num) * 0.75) end
    if unit == 'pt' or unit == 'mm' or unit == 'cm' or unit == 'in' or unit == 'em' then
      return num .. unit
    end
  end
  return nil
end

-- Image inline -> raw Typst `#image("src", ...)`, dropping Pandoc's size box.
-- If the file is missing, emit a dashed placeholder instead so a broken image
-- reference degrades gracefully rather than crashing the whole build.
local function image_to_raw(img)
  local src = img.src
  if not file_exists(src) then
    io.stderr:write("[theme-filters] image not found, using placeholder: " .. tostring(src) .. "\n")
    local name = pandoc.path.filename(tostring(src))
    return pandoc.RawInline('typst',
      '#box(width: 100%, height: 110pt, stroke: (paint: luma(150), thickness: 1pt, dash: "dashed"), '
      .. 'inset: 8pt, radius: 3pt, align(center + horizon, '
      .. 'text(fill: luma(120), size: 0.8em)[нет изображения: ' .. esc_typst_str(name) .. ']))')
  end
  local parts = { '"' .. esc_typst_str(src) .. '"' }
  local w = conv_dim(img.attributes and img.attributes.width)
  local h = conv_dim(img.attributes and img.attributes.height)
  if w then parts[#parts + 1] = 'width: ' .. w end
  if h then parts[#parts + 1] = 'height: ' .. h end
  local alt = pandoc.utils.stringify(img.caption or {})
  if alt and alt ~= '' then
    parts[#parts + 1] = 'alt: "' .. esc_typst_str(alt) .. '"'
  end
  -- NOTE: leading '#' is required — Pandoc places this inside a content
  -- block `[...]`, where a bare `image(...)` would be literal text.
  return pandoc.RawInline('typst', '#image(' .. table.concat(parts, ', ') .. ')')
end

local function write_typst(blocks)
  -- Strip Pandoc's intrinsic-size box() wrapper (see image_to_raw) before
  -- serializing, so columns/assignment images don't overflow.
  local walked = pandoc.walk_block(pandoc.Div(blocks), { Image = image_to_raw })
  local out = pandoc.write(pandoc.Pandoc(walked.content), "typst")
  if type(out) == "table" then return out.output end -- pandoc >= 3.2
  return out                                          -- pandoc < 3.2
end

local function stringify(v)
  if v == nil then return "" end
  return pandoc.utils.stringify(v)
end

local function utf8_lower(s)
  if pandoc.text and pandoc.text.lower then return pandoc.text.lower(s) end
  return s:lower()
end

-- Markdown width attributes -> Typst grid track sizes.
-- Percentages become `fr` so the column-gutter is subtracted from the
-- available width (otherwise 58% + 42% + gutter overflows the slide).
-- "60%" -> 60fr, "0.6" -> 60fr, "40" -> 40fr, "2fr" -> 2fr, "300px" -> 225pt
local function to_typst_width(w)
  if w == nil then return nil end
  w = tostring(w)
  local pct = w:match("^(%d*%.?%d+)%%$")
  if pct then return pct .. "fr" end
  if w:match("^%d*%.?%d+fr$") then return w end
  local abs, unit = w:match("^(%d*%.?%d+)(pt|mm|cm|in|em)$")
  if abs then return abs .. unit end
  local px = w:match("^(%d*%.?%d+)px$")
  if px then return string.format("%gpt", tonumber(px) * 0.75) end
  local num = tonumber(w)
  if num then
    if num <= 1 then num = num * 100 end
    return string.format("%gfr", num)
  end
  return nil
end

-- ::: {.columns} containing ::: {.column width="..."} divs
local function columns_div(el)
  if not el.classes:includes("columns") then return nil end
  local cols, widths = {}, {}
  for _, child in ipairs(el.content) do
    if child.t == "Div" then
      local w = to_typst_width(child.attributes and child.attributes.width)
      cols[#cols + 1] = "[" .. write_typst(child.content) .. "]"
      widths[#widths + 1] = w or "1fr"
    end
  end
  if #cols < 2 then return nil end -- nothing sensible to do; leave as-is
  return pandoc.RawBlock(
    "typst",
    "#two-columns(columns: (" .. table.concat(widths, ", ") .. "))" .. table.concat(cols)
  )
end

local function is_image_block(b)
  if b.t == "Figure" then
    local found = false
    pandoc.walk_block(b, { Image = function() found = true end })
    return found
  end
  if (b.t == "Para" or b.t == "Plain") and #b.content == 1 and b.content[1].t == "Image" then
    return true
  end
  return false
end

local function is_assignment_header(b)
  return b.t == "Header" and b.level == 2
    and utf8_lower(stringify(b.content)):match("^%s*задание%s*$") ~= nil
end

-- `## Задание` slide: text blocks -> left column, image blocks -> right column.
-- Collection stops at the next heading OR at a RawBlock (e.g. a raw
-- `#focus-slide[...]`), because Touying slide-functions must stay at the
-- document's top level and cannot be nested inside a grid/function.
local function make_assignments(blocks)
  local out, i = {}, 1
  while i <= #blocks do
    local b = blocks[i]
    if is_assignment_header(b) then
      local j, content = i + 1, {}
      while j <= #blocks
        and not (blocks[j].t == "Header" and blocks[j].level <= 2)
        and blocks[j].t ~= "RawBlock" do
        content[#content + 1] = blocks[j]
        j = j + 1
      end
      local texts, images = {}, {}
      for _, c in ipairs(content) do
        if is_image_block(c) then
          images[#images + 1] = c
        else
          texts[#texts + 1] = c
        end
      end
      out[#out + 1] = b -- keep the heading so Touying creates the slide
      if #images > 0 and #texts > 0 then
        out[#out + 1] = pandoc.RawBlock(
          "typst",
          "#assignment[" .. write_typst(texts) .. "][" .. write_typst(images) .. "]"
        )
      else
        for _, c in ipairs(content) do out[#out + 1] = c end
      end
      i = j
    else
      out[#out + 1] = b
      i = i + 1
    end
  end
  return out
end

return {
  {
    Pandoc = function(doc)
      local meta = doc.meta

      -- graceful cover-image fallback
      if meta["cover-image"] then
        local p = stringify(meta["cover-image"])
        if not file_exists(p) then
          meta["cover-image"] = nil
          io.stderr:write(
            "[theme-filters] cover-image not found, using light title slide: " .. p .. "\n")
        end
      end

      -- columns divs (bottom-up walk keeps nested divs working)
      local walked = pandoc.walk_block(pandoc.Div(doc.blocks), { Div = columns_div })

      -- `## Задание` slides (detects Image blocks, so run before the global
      -- Image -> raw pass below)
      doc.blocks = make_assignments(walked.content)

      -- Strip Pandoc's intrinsic-size box() from remaining plain figures so
      -- the theme (not the image's pixel size) controls sizing.
      doc.blocks = pandoc.walk_block(pandoc.Div(doc.blocks), { Image = image_to_raw }).content

      doc.meta = meta
      return doc
    end,
  },
}
