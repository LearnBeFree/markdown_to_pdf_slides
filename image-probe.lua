-- image-probe.lua — dump every image reference the Pandoc AST contains.
--
-- A tiny pre-pass used by build.sh: it walks the deck with the SAME --from
-- extensions as the main filter, so Obsidian wikilinks etc. resolve to the
-- exact same src strings. Every image src is printed to stdout as
--   IMG:<src>
-- and the frontmatter cover as
--   COVER:<src>
-- The document itself is emptied, so stdout carries only these lines.
-- This replaces grep-based scanning of the markdown (which saw image
-- syntax inside code fences and missed reference-style images) with the
-- AST as the single source of truth.

function Pandoc(doc)
  local seen = {}
  local lines = {}
  local function note(src)
    if src and src ~= "" and not seen[src] then
      seen[src] = true
      lines[#lines + 1] = "IMG:" .. src
    end
  end
  for _, b in ipairs(doc.blocks) do
    pandoc.walk_block(b, { Image = function(el) note(el.src or "") end })
  end
  if doc.meta["cover-image"] then
    local s = pandoc.utils.stringify(doc.meta["cover-image"])
    if s ~= "" then lines[#lines + 1] = "COVER:" .. s end
  end
  if #lines > 0 then print(table.concat(lines, "\n")) end
  return pandoc.Pandoc({})
end
