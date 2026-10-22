-- One surface: every pane (editor, explorer, terminal, float, focused or not)
-- shows the window's own see-through card, and no highlight group paints a
-- background of its own. In Neovide any explicit background, even one equal to
-- Normal's, is drawn opaque, so a group with a background shows as a darker
-- box: the explorer's rows, the empty rows below a buffer, render-markdown's
-- heading and code boxes, a TODO block.
--
-- A filled background is kept only where it is the meaning: the selection,
-- search hits, the cursor and its line, diff hunks, and the bars (status line,
-- tab line). Every other group loses its background; a "box" style (dark text
-- on a coloured fill, like TODO) becomes the fill's colour as text.
local M = {}

local api = vim.api

local KEEP = {
  "^Normal$",
  -- selection
  "^Visual",
  "Sel$",
  "Selection",
  "^PmenuSel",
  "^PmenuThumb",
  "^WildMenu",
  "^SnippetTabstop",
  "^MultiCursor",
  "^multiple_cursors",
  -- search
  "Search$",
  "^Substitute$",
  -- the cursor and its line
  "Cursor$",
  "^CursorIM$",
  "^CursorLine",
  "^CursorColumn$",
  -- diff hunks
  "^Diff",
  "^GitSigns.*Ln",
  "^GitSigns.*Inline",
  "^GitSigns.*Preview",
  "^MiniDiff",
  -- bars
  "^StatusLine",
  "^TabLine",
  "^WinBar",
  "^lualine",
  "^BufferLine",
  "^Buffer%u",
  "^MiniStatusline",
  "^MiniTabline",
  "^BufTabLine",
  "^NvimTreeStatusLine",
  -- Neovim's redraw debugging
  "^RedrawDebug",
}

local function kept(name)
  for _, pattern in ipairs(KEEP) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

local function luminance(rgb)
  local r, g, b = bit.rshift(rgb, 16) % 256, bit.rshift(rgb, 8) % 256, rgb % 256
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

---Strip the background from every group that is not a selection, search,
---cursor, diff or bar group. Run after the theme and plugins set colours.
function M.apply()
  local base = api.nvim_get_hl(0, { name = "Normal" }).bg or 0
  for name in pairs(api.nvim_get_hl(0, {})) do
    if not kept(name) then
      local hl = api.nvim_get_hl(0, { name = name, link = false })
      if hl.bg then
        local fill = hl.bg
        hl.bg, hl.ctermbg, hl.link, hl.default = nil, nil, nil, nil
        -- Dark text on a coloured fill: keep the colour, as the text.
        -- (render-markdown's heading groups are line fills, not text marks.)
        local dark_text = hl.fg
          and not name:find "^RenderMarkdown"
          and math.abs(luminance(hl.fg) - luminance(base)) < 40
        local bright_fill = luminance(fill) - luminance(base) > 40
        if dark_text and bright_fill then
          hl.fg = fill
        elseif name:find "^RenderMarkdown" and hl.fg and math.abs(luminance(hl.fg) - luminance(base)) < 40 then
          hl.fg = nil
        end
        if hl.reverse then
          hl.reverse = nil
        end
        pcall(api.nvim_set_hl, 0, name, hl)
      end
    end
  end
end

return M
