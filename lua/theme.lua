-- Every colour, built from the desktop's palette (Omarchy colors.toml) with a
-- built-in copy for machines without one (the Mac). One surface: no group
-- paints a background of its own except the selection, search hits, the
-- cursor line, the ruler, diff hunks and the completion choice. Words get
-- colour; boxes do not.
--
-- Two looks, each designed for its own setting:
--   glass  see-through card over wallpaper + blur (Linux). Background, text
--          and opacity come from shell.toml [menu] through the surface-recipe
--          hook, so Neovide matches kitty, Files and the shell popups. In a
--          terminal (kitty, also inside tmux) Neovim paints no background at
--          all: kitty's own card (the same [menu] colour and opacity, Hyprland
--          blur) shows through every pane and float, and the [menu] colour is
--          only what dims and tints are mixed toward.
--   flat   opaque (the Mac, or transparency off). The theme's dark editor
--          background (dark_background) under its own text, so body
--          text, comments and the dim are at least as clear as the old
--          config's opaque look; the cursor line is a faint band.
local M = {}

local api = vim.api

-- Everforest Night, the desktop theme as of 2026-10 (fallback palette).
local FALLBACK = {
  background = "#161a1c",
  dark_background = "#121517",
  foreground = "#e6dcc3",
  accent = "#7ad5c9",
  selection = "#4a3440",
  muted = "#6a766f",
  dark_foreground = "#7a8478",
  light_foreground = "#9da9a0",
  red = "#ff797c",
  orange = "#ff9f74",
  yellow = "#fcce73",
  green = "#b5db7a",
  cyan = "#7eda94",
  blue = "#7ad5c9",
  magenta = "#ee95c0",
}

local function read_palette()
  local palette = vim.deepcopy(FALLBACK)
  local file = io.open(vim.fn.expand "~/.local/state/omarchy/current/theme/colors.toml")
  if file then
    for line in file:lines() do
      local key, value = line:match '^%s*([%w_]+)%s*=%s*"(#%x%x%x%x%x%x)"'
      if key then
        palette[key] = value
      end
      palette.mode = line:match '^%s*mode%s*=%s*"(%a+)"' or palette.mode
    end
    file:close()
  end
  return palette
end

-- shell.toml [menu] (opacity, bg, fg), which the surface-recipe hook writes to
-- ~/.config/nvim/lua/surface.lua. A copy of this config elsewhere without its
-- own (a worktree) reads that file; none at all (the Mac) gives nil: flat.
local function read_surface()
  local ok, surface = pcall(require, "surface")
  if ok and type(surface) == "table" then
    return surface
  end
  local path = vim.fn.expand "~/.config/nvim/lua/surface.lua"
  if vim.uv.fs_stat(path) then
    ok, surface = pcall(dofile, path)
    if ok and type(surface) == "table" then
      return surface
    end
  end
end

local function rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

---Colour `t` of the way from `a` to `b`.
function M.mix(a, b, t)
  local r1, g1, b1 = rgb(a)
  local r2, g2, b2 = rgb(b)
  local function c(x, y)
    return math.floor(x + (y - x) * t + 0.5)
  end
  return string.format("#%02x%02x%02x", c(r1, r2), c(g1, g2), c(b1, b2))
end

local function groups(p, look)
  local bg, fg = p.bg, p.fg
  local mix = M.mix
  local comment = p.light_foreground
  local faint = mix(bg, fg, 0.32)
  local line = mix(bg, fg, 0.24)
  local band = mix(bg, fg, 0.05)
  local c = p -- the theme's named colours: c.red, c.accent, ...
  return {
    -- The one surface
    Normal = { fg = fg, bg = not p.see_through and bg or nil },
    NormalNC = { link = "Normal" },
    NormalFloat = { link = "Normal" },
    FloatBorder = { fg = mix(bg, fg, 0.28) },
    FloatTitle = { fg = c.accent, bold = true },
    FloatFooter = { fg = comment },
    WinSeparator = { fg = line },
    WinSeparatorHover = { fg = c.accent },
    EndOfBuffer = { fg = bg },
    -- Gutter
    LineNr = { fg = faint },
    CursorLineNr = { fg = fg, bold = true },
    SignColumn = {},
    FoldColumn = { fg = faint },
    Folded = { fg = comment, italic = true },
    -- Cursor and selection
    Cursor = { fg = bg, bg = fg },
    CursorLine = look == "flat" and { bg = band } or {},
    CursorColumn = look == "flat" and { bg = band } or {},
    ColorColumn = { bg = mix(bg, fg, 0.1) },
    Visual = { bg = p.selection },
    VisualNOS = { bg = p.selection },
    Search = { fg = fg, bg = mix(bg, c.yellow, 0.28) },
    CurSearch = { fg = bg, bg = c.yellow },
    IncSearch = { link = "CurSearch" },
    Substitute = { fg = bg, bg = c.orange },
    MatchParen = { fg = c.accent, bold = true, underline = true },
    WordOccurrence = { underline = true, sp = c.accent },
    -- Bars: words on the surface, the active one bright
    StatusLine = { fg = fg },
    StatusLineNC = { fg = comment },
    StatusLineDim = { fg = comment },
    StatusLineAccent = { fg = c.accent, bold = true },
    -- The mode as coloured text, never a filled block.
    StatusLineModeNormal = { fg = c.green, bold = true },
    StatusLineModeInsert = { fg = c.blue, bold = true },
    StatusLineModeVisual = { fg = c.magenta, bold = true },
    StatusLineModeReplace = { fg = c.red, bold = true },
    StatusLineModeCommand = { fg = c.yellow, bold = true },
    StatusLineModeTerminal = { fg = c.cyan, bold = true },
    TabLine = { fg = comment },
    TabLineFill = {},
    TabLineSel = { fg = fg, bold = true },
    WinBar = { fg = fg, bold = true },
    WinBarNC = { fg = comment },
    -- Popup menu: the chosen item is the only filled row
    Pmenu = { fg = fg },
    ListCurrent = { bg = p.selection },
    PmenuSel = { bg = p.selection, bold = true },
    PmenuKind = { fg = c.blue },
    PmenuKindSel = { fg = c.blue, bg = p.selection },
    PmenuExtra = { fg = comment },
    PmenuExtraSel = { fg = comment, bg = p.selection },
    PmenuMatch = { fg = c.accent, bold = true },
    PmenuMatchSel = { fg = c.accent, bg = p.selection, bold = true },
    PmenuSbar = {},
    PmenuThumb = { bg = line },
    ComplMatchIns = { fg = comment },
    -- Text that is not the file's words
    NonText = { fg = faint },
    Whitespace = { fg = line },
    SpecialKey = { fg = faint },
    Conceal = { fg = comment },
    Directory = { fg = c.blue },
    Title = { fg = c.green, bold = true },
    Question = { fg = c.green },
    MoreMsg = { fg = c.green },
    ModeMsg = { fg = fg, bold = true },
    MsgArea = { fg = fg },
    ErrorMsg = { fg = c.red, bold = true },
    WarningMsg = { fg = c.yellow },
    QuickFixLine = { bold = true },
    SpellBad = { undercurl = true, sp = c.red },
    SpellCap = { undercurl = true, sp = c.yellow },
    SpellLocal = { undercurl = true, sp = c.blue },
    SpellRare = { undercurl = true, sp = c.magenta },
    -- Diff hunks keep a fill: the colour is the meaning
    DiffAdd = { bg = mix(bg, c.green, 0.16) },
    DiffChange = { bg = mix(bg, c.blue, 0.12) },
    DiffDelete = { fg = c.red, bg = mix(bg, c.red, 0.14) },
    DiffText = { bg = mix(bg, c.blue, 0.3) },
    Added = { fg = c.green },
    Changed = { fg = c.blue },
    Removed = { fg = c.red },
    -- Diagnostics: coloured words and undercurls, never boxes
    DiagnosticError = { fg = c.red },
    DiagnosticWarn = { fg = c.yellow },
    DiagnosticInfo = { fg = c.blue },
    DiagnosticHint = { fg = c.cyan },
    DiagnosticOk = { fg = c.green },
    DiagnosticUnderlineError = { undercurl = true, sp = c.red },
    DiagnosticUnderlineWarn = { undercurl = true, sp = c.yellow },
    DiagnosticUnderlineInfo = { undercurl = true, sp = c.blue },
    DiagnosticUnderlineHint = { undercurl = true, sp = c.cyan },
    DiagnosticUnderlineOk = { undercurl = true, sp = c.green },
    DiagnosticVirtualTextError = { fg = mix(c.red, bg, 0.2) },
    DiagnosticVirtualTextWarn = { fg = mix(c.yellow, bg, 0.2) },
    DiagnosticVirtualTextInfo = { fg = mix(c.blue, bg, 0.2) },
    DiagnosticVirtualTextHint = { fg = mix(c.cyan, bg, 0.2) },
    DiagnosticUnnecessary = { fg = comment },
    DiagnosticDeprecated = { strikethrough = true },
    LspReferenceText = { underline = true, sp = faint },
    LspReferenceRead = { underline = true, sp = faint },
    LspReferenceWrite = { underline = true, sp = c.orange },
    LspInlayHint = { fg = faint, italic = true },
    LspSignatureActiveParameter = { fg = c.accent, bold = true, underline = true },
    -- Code
    Comment = { fg = comment, italic = true },
    Constant = { fg = c.magenta },
    String = { fg = c.cyan },
    Character = { fg = c.cyan },
    Number = { fg = c.magenta },
    Boolean = { fg = c.magenta },
    Float = { fg = c.magenta },
    Identifier = { fg = fg },
    Function = { fg = c.green },
    Statement = { fg = c.red },
    Conditional = { fg = c.red },
    Repeat = { fg = c.red },
    Label = { fg = c.orange },
    Operator = { fg = c.orange },
    Keyword = { fg = c.red },
    Exception = { fg = c.red },
    PreProc = { fg = c.magenta },
    Include = { fg = c.red },
    Define = { fg = c.magenta },
    Macro = { fg = c.magenta },
    Type = { fg = c.yellow },
    StorageClass = { fg = c.orange },
    Structure = { fg = c.yellow },
    Typedef = { fg = c.yellow },
    Special = { fg = c.yellow },
    SpecialChar = { fg = c.yellow },
    Tag = { fg = c.orange },
    Delimiter = { fg = comment },
    SpecialComment = { fg = comment, italic = true },
    Debug = { fg = c.orange },
    Underlined = { underline = true },
    Ignore = { fg = faint },
    Error = { fg = c.red },
    Todo = { fg = c.accent, bold = true },
    TodoTextTodo = { fg = c.accent, bold = true },
    TodoTextFix = { fg = c.red, bold = true },
    TodoTextWarn = { fg = c.yellow, bold = true },
    TodoTextNote = { fg = c.blue, bold = true },
    ["@variable"] = { fg = fg },
    ["@variable.builtin"] = { fg = c.magenta, italic = true },
    ["@variable.parameter"] = { fg = fg },
    ["@variable.member"] = { fg = c.blue },
    ["@property"] = { fg = c.blue },
    ["@constant"] = { fg = c.magenta },
    ["@constant.builtin"] = { fg = c.magenta },
    ["@module"] = { fg = c.yellow, italic = true },
    ["@label"] = { fg = c.orange },
    ["@string"] = { fg = c.cyan },
    ["@string.escape"] = { fg = c.green },
    ["@string.special"] = { fg = c.yellow },
    ["@string.special.url"] = { fg = c.cyan, underline = true },
    ["@character"] = { fg = c.cyan },
    ["@number"] = { fg = c.magenta },
    ["@boolean"] = { fg = c.magenta },
    ["@type"] = { fg = c.yellow },
    ["@type.builtin"] = { fg = c.yellow, italic = true },
    ["@attribute"] = { fg = c.magenta },
    ["@function"] = { fg = c.green },
    ["@function.builtin"] = { fg = c.green },
    ["@function.method"] = { fg = c.green },
    ["@constructor"] = { fg = c.blue },
    -- ocamllsp tags variant constructors as enum members (Neovim's default:
    -- a constant); one colour for `Some` and `Fight` alike.
    ["@lsp.type.enumMember"] = { link = "@constructor" },
    ["@operator"] = { fg = c.orange },
    ["@keyword"] = { fg = c.red },
    ["@punctuation"] = { fg = comment },
    ["@punctuation.special"] = { fg = c.blue },
    ["@comment"] = { link = "Comment" },
    ["@comment.todo"] = { fg = c.accent, bold = true },
    ["@comment.note"] = { fg = c.blue, bold = true },
    ["@comment.warning"] = { fg = c.yellow, bold = true },
    ["@comment.error"] = { fg = c.red, bold = true },
    ["@tag"] = { fg = c.orange },
    ["@tag.attribute"] = { fg = c.yellow },
    ["@tag.delimiter"] = { fg = comment },
    ["@diff.plus"] = { fg = c.green },
    ["@diff.minus"] = { fg = c.red },
    ["@diff.delta"] = { fg = c.blue },
    -- Markup: headings and code coloured; every marker stays visible
    ["@markup.heading"] = { fg = c.orange, bold = true },
    ["@markup.heading.1"] = { fg = c.red, bold = true },
    ["@markup.heading.2"] = { fg = c.orange, bold = true },
    ["@markup.heading.3"] = { fg = c.yellow, bold = true },
    ["@markup.heading.4"] = { fg = c.green, bold = true },
    ["@markup.heading.5"] = { fg = c.blue, bold = true },
    ["@markup.heading.6"] = { fg = c.magenta, bold = true },
    ["@markup.strong"] = { bold = true },
    ["@markup.italic"] = { italic = true },
    ["@markup.strikethrough"] = { strikethrough = true },
    ["@markup.underline"] = { underline = true },
    ["@markup.quote"] = { fg = comment, italic = true },
    ["@markup.math"] = { fg = c.yellow },
    ["@markup.link"] = { fg = c.blue },
    ["@markup.link.label"] = { fg = c.blue, underline = true },
    ["@markup.link.url"] = { fg = c.cyan, underline = true },
    ["@markup.raw"] = { fg = c.cyan },
    ["@markup.list"] = { fg = c.orange },
    ["@markup.list.checked"] = { fg = c.green },
    ["@markup.list.unchecked"] = { fg = comment },
    -- Plugins
    MiniDiffSignAdd = { fg = c.green },
    MiniDiffSignChange = { fg = c.blue },
    MiniDiffSignDelete = { fg = c.red },
    -- The tab bar (tabs.lua): words, the current tab underlined
    TabsCurrent = { fg = fg, bold = true, underline = true, sp = c.accent },
    TabsVisible = { fg = fg },
    TabsHidden = { fg = comment },
    TabsModifiedCurrent = { fg = c.orange, bold = true, underline = true, sp = c.accent },
    TabsModifiedVisible = { fg = c.orange },
    TabsModifiedHidden = { fg = mix(c.orange, bg, 0.35) },
    TabsError = { fg = c.red, bold = true },
    TabsClose = { fg = comment },
    TabsFill = {},
    TabsTabpage = { fg = c.accent, bold = true },
    TabsTrunc = { fg = comment, bold = true },
    MiniPickBorder = { link = "FloatBorder" },
    MiniPickBorderBusy = { fg = c.yellow },
    MiniPickBorderText = { fg = c.accent, bold = true },
    MiniPickNormal = { link = "Normal" },
    MiniPickPrompt = { fg = c.accent, bold = true },
    MiniPickPromptCaret = { fg = c.accent },
    MiniPickPromptPrefix = { fg = c.accent },
    MiniPickMatchCurrent = { bg = p.selection, bold = true },
    MiniPickMatchMarked = { fg = c.yellow, bold = true },
    MiniPickMatchRanges = { fg = c.accent, bold = true },
    MiniPickHeader = { fg = c.accent, bold = true },
    MiniPickIconDirectory = { fg = c.blue },
    MiniPickIconFile = { fg = fg },
    MiniPickPreviewLine = { bg = band },
    MiniPickPreviewRegion = { bg = p.selection },
    -- Alt/Cmd+O (projects.lua): recent projects get the accent clock and
    -- their age; every folder's own name is bold.
    PickFolderIcon = { link = "MiniPickIconDirectory" },
    PickFolderRecent = { fg = c.accent },
    PickFolderAge = { fg = comment },
    PickFolderName = { bold = true },
    MiniIconsAzure = { fg = c.blue },
    MiniIconsBlue = { fg = c.blue },
    MiniIconsCyan = { fg = c.cyan },
    MiniIconsGreen = { fg = c.green },
    MiniIconsGrey = { fg = comment },
    MiniIconsOrange = { fg = c.orange },
    MiniIconsPurple = { fg = c.magenta },
    MiniIconsRed = { fg = c.red },
    MiniIconsYellow = { fg = c.yellow },
    NvimTreeNormal = { link = "Normal" },
    NvimTreeNormalNC = { link = "Normal" },
    NvimTreeNormalFloat = { link = "Normal" },
    NvimTreeEndOfBuffer = { link = "EndOfBuffer" },
    NvimTreeWinSeparator = { link = "WinSeparator" },
    -- The row you are on in a list has one fill everywhere, in both looks:
    -- the tree's row, the finder's and the completion menu's current item.
    -- (An editor's cursor line is not a list row: glass marks it with the
    -- line number only.) Shown only in the focused pane (focus.lua).
    NvimTreeCursorLine = { link = "ListCurrent" },
    NvimTreeSignColumn = {},
    NvimTreeRootFolder = { fg = c.accent, bold = true },
    -- Folders green, files in the text colour: the two read apart at a
    -- glance (the old config's tree).
    NvimTreeFolderName = { fg = c.green },
    NvimTreeOpenedFolderName = { fg = c.green, bold = true },
    NvimTreeEmptyFolderName = { fg = comment },
    NvimTreeFolderIcon = { fg = c.blue },
    NvimTreeFolderArrowClosed = { fg = comment },
    NvimTreeFolderArrowOpen = { fg = comment },
    NvimTreeIndentMarker = { fg = line },
    NvimTreeOpenedHL = { fg = c.accent },
    NvimTreeExecFile = { fg = c.green },
    NvimTreeSpecialFile = { fg = c.yellow },
    NvimTreeSymlink = { fg = c.cyan },
    NvimTreeImageFile = { fg = fg },
    NvimTreeModifiedIcon = { fg = c.orange },
    NvimTreeGitDirtyIcon = { fg = c.orange },
    NvimTreeGitStagedIcon = { fg = c.green },
    NvimTreeGitNewIcon = { fg = c.green },
    NvimTreeGitDeletedIcon = { fg = c.red },
    NvimTreeGitRenamedIcon = { fg = c.yellow },
    NvimTreeGitIgnoredIcon = { fg = faint },
    NvimTreeGitMergeIcon = { fg = c.magenta },
    NvimTreeGitFileDirtyHL = { fg = c.orange },
    NvimTreeGitFileNewHL = { fg = c.green },
    NvimTreeGitFileStagedHL = { fg = c.green },
    NvimTreeGitFolderDirtyHL = { fg = c.orange },
    NvimTreeGitFolderNewHL = { fg = c.green },
    NvimTreeWindowPicker = { fg = bg, bg = c.accent, bold = true },
    NvimTreeLiveFilterPrefix = { fg = c.accent, bold = true },
    NvimTreeLiveFilterValue = { fg = fg, bold = true },
    -- The tree's Sort row (explorer.lua winbar)
    ExplorerSortTitle = { fg = comment },
    ExplorerSortButton = { fg = fg },
    ExplorerSortActive = { fg = c.accent, bold = true },
  }
end

-- Groups allowed to keep a background (the meaning is the fill).
local KEEP_BG = {
  "^Normal$",
  "^Visual",
  "Sel$",
  "^PmenuThumb",
  "Search$",
  "^Substitute$",
  "Cursor$",
  "^CursorIM$",
  "^CursorLine",
  "^ListCurrent$",
  "^CursorColumn$",
  "^ColorColumn$",
  "^Diff",
  "^MiniDiffOver",
  "^Snippet",
  "^MiniPickMatchCurrent",
  "^MiniPickPreview",
  "^NvimTreeWindowPicker",
  "^TermCursor",
  "^RedrawDebug",
}

local function keeps_bg(name)
  for _, pattern in ipairs(KEEP_BG) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

---Safety net for groups a plugin defines on its own: drop any background
---that is not a selection, search, cursor or diff fill.
function M.one_surface()
  for name, hl in pairs(api.nvim_get_hl(0, {})) do
    -- A link takes its fill from its target, which is judged on its own
    -- (stripping NvimTreeCursorLine -> ListCurrent would lose the row fill).
    if not hl.link and not keeps_bg(name) and (hl.bg or hl.reverse) then
      hl.bg, hl.ctermbg, hl.reverse, hl.default = nil, nil, nil, nil
      pcall(api.nvim_set_hl, 0, name, hl)
    end
  end
end

-- Set by apply(): the palette with the surface's bg/fg, and "glass" or "flat".
M.palette, M.look = nil, nil

---Build and set every group for the current look.
function M.apply()
  local p = read_palette()
  local surface = read_surface()
  local look = vim.g.look
  if look ~= "glass" and look ~= "flat" then
    look = surface and "glass" or "flat"
  end
  if look == "glass" and surface then
    p.bg, p.fg = surface.bg, surface.fg
    p.see_through = not vim.g.neovide
  else
    p.bg, p.fg = p.dark_background, p.foreground
  end
  M.palette, M.look = p, look

  vim.cmd "highlight clear"
  vim.o.background = p.mode == "light" and "light" or "dark"
  vim.g.colors_name = "surface"
  for name, spec in pairs(groups(p, look)) do
    api.nvim_set_hl(0, name, spec)
  end
  -- Terminal colours: the same 16 as Omarchy's own terminals (kitty.conf);
  -- a bright colour the theme lacks is its plain one mixed toward the text.
  local term = { p.background, p.red, p.green, p.yellow, p.blue, p.magenta, p.cyan, p.foreground }
  local bright = {
    p.muted,
    p.bright_red,
    p.bright_green,
    p.bright_yellow,
    p.bright_blue,
    p.bright_magenta,
    p.bright_cyan,
    p.bright_foreground,
  }
  for i, colour in ipairs(term) do
    vim.g["terminal_color_" .. (i - 1)] = colour
    vim.g["terminal_color_" .. (i + 7)] = bright[i] or M.mix(colour, p.foreground, 0.25)
  end

  -- Glass: only the line number marks the cursor line (a filled band would be
  -- the one opaque strip on the glass). Flat: a faint band across the pane.
  vim.o.cursorlineopt = look == "flat" and "both" or "number"
  if vim.g.neovide then
    vim.g.neovide_opacity = 1.0
    vim.g.neovide_normal_opacity = (look == "glass" and surface) and surface.opacity or 1.0
  end
  M.one_surface()
  api.nvim_exec_autocmds("ColorScheme", { pattern = "surface", modeline = false })
end

function M.setup()
  M.apply()
  api.nvim_create_user_command("Look", function(args)
    vim.g.look = args.args ~= "" and args.args or nil
    M.apply()
  end, {
    nargs = "?",
    complete = function()
      return { "glass", "flat" }
    end,
    desc = "Switch between the glass and flat look",
  })
  -- Plugins that define their colours late (orgmode on the first .org file).
  api.nvim_create_autocmd({ "VimEnter", "FileType" }, {
    group = api.nvim_create_augroup("OneSurface", { clear = true }),
    callback = function(args)
      if args.event == "VimEnter" or args.match == "org" then
        vim.schedule(M.one_surface)
      end
    end,
  })
end

return M
