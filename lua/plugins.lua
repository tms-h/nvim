-- The plugins, each for a job Neovim 0.12 does not do on its own. Managed by
-- the built-in vim.pack (:lua vim.pack.update() to update; versions are
-- pinned in nvim-pack-lock.json).
--
--   mini.nvim        finder (mini.pick), completion, key hints (mini.clue),
--                    TODO words (mini.hipatterns), git signs (mini.diff),
--                    icons, bracket pairs, smooth scrolling (mini.animate)
--   nvim-tree.lua    the file tree
--   nvim-treesitter  installs the OCaml, Python, Rust... parsers
--   orgmode          README.org files (loaded on the first .org file)
--   mason.nvim       installs language servers (loaded by :Mason)
--   vim-wakatime     time tracking, when ~/.wakatime.cfg exists
--   hardtime.nvim    blocks hjkl/arrow spam, hints better motions (nui.nvim
--                    draws its :Hardtime report)
--   flash.nvim       s jumps: type a couple of letters, press the label on
--                    the match you want
--   vim-surround     add, change, delete brackets and quotes around text
--                    (ys, cs, ds, visual S); vim-repeat lets . repeat them
-- vim-surround's keys are set in keys.lua, with names for the key hints.
vim.g.surround_no_mappings = 1
-- While cs, ds or visual S wait for the bracket, the cursor sat on the
-- command line: their <Plug> keys run `:<C-U>call ...`, which opens it, and
-- with 'cmdheight' 0 that is a hidden grid. Neovide drew the cursor in the
-- top-left cell, on the tab bar, so S looked like a jump (2026-11-13). The
-- same calls through <Cmd> or Lua never open the command line (a selection
-- is left with <Esc> first, which sets the '< '> marks the plugin reads).
vim.api.nvim_create_autocmd("SourcePost", {
  group = vim.api.nvim_create_augroup("SurroundCursor", { clear = true }),
  pattern = "*/vim-surround/plugin/surround.vim",
  callback = function(args)
    local info = vim.fn.getscriptinfo({ name = args.match })[1]
    if not info then
      return
    end
    local f = ("<SNR>%d_"):format(info.sid)
    local function call(plug, body, desc)
      vim.keymap.set("n", plug, "<Cmd>call " .. f .. body .. "<CR>", { silent = true, desc = desc })
    end
    call("<Plug>Dsurround", ("dosurround(%sinputtarget())"):format(f), "Surround: delete (ds)")
    call("<Plug>Csurround", "changesurround()", "Surround: change (cs)")
    call("<Plug>CSurround", "changesurround(1)", "Surround: change, new pair on its own lines (cS)")
    -- Visual S / gS. A characterwise selection that takes in the line break
    -- (v$, or ending past the last letter) is cut back to the line's last
    -- letter, and one that starts on a line break begins on the next line:
    -- v$S) put the `)` at the start of the next line, before its `|>`
    -- ("when i S) it makes a new line", 2026-11-13). V + S) keeps vim-
    -- surround's own block: the pair on lines of their own.
    local function visual(block_when_linewise)
      return function()
        vim.cmd "normal! \27"
        local mode = vim.fn.visualmode()
        if mode == "v" then
          local s, e = vim.fn.getpos "'<", vim.fn.getpos "'>"
          local last = vim.fn.getline(e[2])
          if e[3] > #last and #last > 0 then
            e[3] = #last - #vim.fn.strcharpart(last, vim.fn.strchars(last) - 1) + 1
            vim.fn.setpos("'>", e)
          end
          if s[3] > #vim.fn.getline(s[2]) and s[2] < e[2] then
            vim.fn.setpos("'<", { 0, s[2] + 1, 1, 0 })
          end
        end
        vim.fn[f .. "opfunc"](mode, (mode == "V") == block_when_linewise and 1 or 0)
      end
    end
    vim.keymap.set("x", "<Plug>VSurround", visual(true), { silent = true, desc = "Surround: wrap the selection (S)" })
    vim.keymap.set(
      "x",
      "<Plug>VgSurround",
      visual(false),
      { silent = true, desc = "Surround: wrap the selection, indented (gS)" }
    )
  end,
})

local gh = function(repo)
  return "https://github.com/" .. repo
end
local later = function(src)
  -- Install now, load when first needed (see "Loaded when needed" below).
  return { src = src, data = { later = true } }
end

vim.pack.add({
  gh "nvim-mini/mini.nvim",
  gh "nvim-tree/nvim-tree.lua",
  { src = gh "nvim-treesitter/nvim-treesitter", version = "main" },
  gh "MunifTanjim/nui.nvim",
  gh "m4xshen/hardtime.nvim",
  gh "folke/flash.nvim",
  gh "tpope/vim-surround",
  gh "tpope/vim-repeat",
  later(gh "nvim-orgmode/orgmode"),
  later(gh "mason-org/mason.nvim"),
  later(gh "wakatime/vim-wakatime"),
}, {
  confirm = false,
  load = function(plug)
    if not (plug.spec.data and plug.spec.data.later) then
      vim.cmd.packadd { plug.spec.name, bang = true }
    end
  end,
})

-- ── mini.nvim ──────────────────────────────────────────────────────────────
require("mini.icons").setup()
MiniIcons.mock_nvim_web_devicons()
require("tabs").setup() -- the tab bar (tabs.lua)
require("mini.diff").setup {
  view = { style = "sign", signs = { add = "▎", change = "▎", delete = "▁" } },
}
require("mini.pairs").setup {
  modes = { insert = true, command = false, terminal = false },
}
-- Completion as you type: language server items, else words in the buffer.
-- Docs and signatures show in small floats.
require("mini.completion").setup {
  delay = { completion = 80, info = 200, signature = 80 },
  window = {
    info = { height = 20, width = 70, border = "rounded" },
    signature = { height = 10, width = 80, border = "rounded" },
  },
  -- Set per buffer when a language server attaches (lsp.lua), so other
  -- filetypes (org) keep their own omnifunc.
  lsp_completion = { source_func = "omnifunc", auto_setup = false },
  mappings = { force_twostep = "<C-Space>", force_fallback = "", scroll_down = "<C-f>", scroll_up = "<C-b>" },
}
-- ocamllsp answers signatureHelp with activeParameter = null (LSP 3.18: no
-- parameter is active), even when told the client can't take it. mini.completion
-- compares that with a number and errors on every keystroke inside a call
-- ("attempt to compare number with userdata", completion.lua:1695, mini.nvim
-- a6e2313). Turn null into -1 (out of range, so nothing is highlighted) before
-- mini sees it. Drop this once mini.nvim handles vim.NIL there.
local function no_null_active(res)
  if type(res) ~= "table" then
    return
  end
  if res.activeSignature == vim.NIL then
    res.activeSignature = nil
  end
  if res.activeParameter == vim.NIL then
    res.activeParameter = -1
  end
  for _, sig in ipairs(type(res.signatures) == "table" and res.signatures or {}) do
    if sig.activeParameter == vim.NIL then
      sig.activeParameter = -1
    end
  end
end
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("SignatureNullFix", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client._no_null_active then
      return
    end
    client._no_null_active = true
    local request = client.request
    client.request = function(self, method, params, handler, bufnr)
      if method == "textDocument/signatureHelp" and handler then
        local inner = handler
        handler = function(err, result, ...)
          no_null_active(result)
          return inner(err, result, ...)
        end
      end
      return request(self, method, params, handler, bufnr)
    end
  end,
})
-- TODO / FIXME / HACK / NOTE in comments: coloured words, never a filled
-- block (TodoText* in theme.lua). Outside a comment (a string, prose with
-- no tree-sitter comment) they stay plain, when tree-sitter can tell.
local function in_comment(buf, row, col)
  -- Tree-sitter parses in the background, and this can run first (busy
  -- machine, big file): parse the row now, or no capture says "comment" and
  -- the word stays plain until the next edit. A no-op once parsed.
  -- No parser for the buffer: get_parser returns nil (it no longer throws).
  local ok_parser, parser = pcall(vim.treesitter.get_parser, buf)
  parser = ok_parser and parser or nil
  if parser then
    parser:parse { row, row + 1 }
  end
  local ok, captures = pcall(vim.treesitter.get_captures_at_pos, buf, row, col)
  if not ok or #captures == 0 then
    -- No parser: tree-sitter cannot tell, so colour it.
    return parser == nil
  end
  for _, c in ipairs(captures) do
    if c.capture:find "comment" then
      return true
    end
  end
  return false
end
local function todo_word(words, group)
  return {
    pattern = vim.tbl_map(function(w)
      return "%f[%w]()" .. w .. "()%f[%W]"
    end, words),
    group = function(buf, _, data)
      if in_comment(buf, data.line - 1, data.from_col - 1) then
        return group
      end
    end,
  }
end
require("mini.hipatterns").setup {
  highlighters = {
    todo = todo_word({ "TODO", "PERF" }, "TodoTextTodo"),
    fixme = todo_word({ "FIXME", "BUG" }, "TodoTextFix"),
    hack = todo_word({ "HACK", "WARN", "XXX" }, "TodoTextWarn"),
    note = todo_word({ "NOTE" }, "TodoTextNote"),
  },
}

-- Smooth scrolling in terminal Neovim (herdr, tmux, kitty): every scroll
-- (Ctrl+D/U/F/B, zz, gg/G, search jumps, wheel) glides in 120 ms. Neovide
-- animates scrolling itself (gui.lua). Only scrolling is animated.
if not vim.g.neovide then
  local animate = require "mini.animate"
  animate.setup {
    scroll = { timing = animate.gen_timing.linear { duration = 120, unit = "total" } },
    cursor = { enable = false },
    resize = { enable = false },
    open = { enable = false },
    close = { enable = false },
  }
end

-- OCaml type variables ('a) and Rust lifetimes ('a) are not quotes.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "ocaml", "ocaml_interface", "rust" },
  callback = function(args)
    vim.keymap.set("i", "'", "'", { buffer = args.buf })
  end,
})

-- Key hints: pause after Space and the keys that can follow pop up in the
-- corner (like which-key).
require("mini.clue").setup {
  triggers = {
    { mode = "n", keys = "<Leader>" },
    { mode = "x", keys = "<Leader>" },
  },
  -- Every Space group has a name, in both modes (a nameless one showed as
  -- "+2 choices"). Space o holds the OCaml keys in OCaml files and orgmode's
  -- keys elsewhere (its agenda and capture are global); org's own subgroups
  -- are named per buffer (below).
  clues = {
    { mode = "n", keys = "<Leader>f", desc = "+Find" },
    { mode = { "n", "x" }, keys = "<Leader>g", desc = "+Git changes" },
    {
      mode = { "n", "x" },
      keys = "<Leader>o",
      desc = function()
        return vim.bo.filetype:find "^ocaml" and "+OCaml" or "+Org"
      end,
    },
    { mode = "n", keys = "<Leader>h", desc = "+Hardtime" },
    { mode = "n", keys = "<Leader>i", desc = "+Iron" },
  },
  window = { delay = 400, config = { width = "auto", border = "rounded" } },
}
-- mini.clue only adds its Space trigger to listed buffers. Scratch buffers
-- (fe-nvim's todo and review, the tree, Goose) are unlisted, so there Space
-- hit the global <Nop> and the next key ran as a plain command: Space o gave
-- E21 in the read-only todo. Add the trigger when such a buffer is shown.
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("ClueUnlisted", { clear = true }),
  callback = vim.schedule_wrap(function(args)
    if vim.api.nvim_buf_is_valid(args.buf) and not vim.bo[args.buf].buflisted then
      MiniClue.ensure_buf_triggers(args.buf)
    end
  end),
})

-- The finder: set up on first use (finder.lua).
require("finder").setup()

-- ── hardtime.nvim ──────────────────────────────────────────────────────────
-- Habit trainer with some restrictions: a 5th h/j/k/l/+/gj/gk within a second
-- is blocked (a count like 5j or an edit resets it); arrows do nothing in
-- Normal and Visual but still move in Insert; the mouse stays. Hints for
-- better motions show either way. Space h t toggles, Space h r reports.
require("hardtime").setup {
  restriction_mode = "block",
  max_count = 4,
  disable_mouse = false,
  disabled_keys = {
    ["<Up>"] = { "n", "x" },
    ["<Down>"] = { "n", "x" },
    ["<Left>"] = { "n", "x" },
    ["<Right>"] = { "n", "x" },
  },
}

-- ── flash.nvim ─────────────────────────────────────────────────────────────
-- s (keys.lua): type a couple of letters, every visible match in every pane
-- gets a label (FlashLabel, theme.lua), press it to jump. Its add-ons to f, t
-- and / stay off, so those keys work as stock.
require("flash").setup {
  modes = { search = { enabled = false }, char = { enabled = false } },
}

-- ── Tree-sitter ────────────────────────────────────────────────────────────
-- Parsers this config needs beyond the ones Neovim ships (lua, markdown,
-- vimdoc, c, query). Installed once, in the background.
local parsers = { "ocaml", "ocaml_interface", "python", "rust", "toml", "json", "bash", "yaml" }
-- A language counts as installed only when its parser and highlight queries
-- both load. The queries are links into the plugin's folder: renaming the data
-- folder (nvim-next -> nvim, 2026-10-25) left them dead while the parsers
-- stayed, and OCaml lost every colour but the language server's.
local function missing_parsers()
  return vim.tbl_filter(function(lang)
    return #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) == 0
      or #vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false) == 0
  end, parsers)
end
vim.schedule(function()
  local missing = missing_parsers()
  if #missing > 0 and require("tools").find "tree-sitter" then
    -- force: a parser already in place still gets its query link redone.
    require("nvim-treesitter").install(missing, { force = true })
  end
end)
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
  callback = function(args)
    if pcall(vim.treesitter.start, args.buf) and args.match ~= "ocaml" and args.match ~= "ocaml_interface" then
      -- OCaml indents with ocp-indent (ocaml.lua).
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- ── Loaded when needed ─────────────────────────────────────────────────────
-- orgmode's Space o subgroups, named in org files only.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  callback = function(args)
    local groups = { b = "+Code blocks", d = "+Dates", i = "+Insert", l = "+Links", n = "+Notes", x = "+Clock" }
    local clues = {}
    for k, desc in pairs(groups) do
      clues[#clues + 1] = { mode = { "n", "x" }, keys = "<Leader>o" .. k, desc = desc }
    end
    vim.b[args.buf].miniclue_config = { clues = clues }
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  once = true,
  callback = function(args)
    vim.cmd.packadd "orgmode"
    require("orgmode").setup {
      org_agenda_files = {},
      org_hide_emphasis_markers = false,
      org_hide_leading_stars = false,
      org_startup_indented = false,
      org_startup_folded = "showeverything",
      ui = { folds = { colored = true } },
    }
    -- Re-run the FileType setup for the buffer that triggered the load.
    vim.api.nvim_exec_autocmds("FileType", { buffer = args.buf })
  end,
})

vim.api.nvim_create_user_command("Mason", function(args)
  vim.api.nvim_del_user_command "Mason"
  vim.cmd.packadd "mason.nvim"
  require("mason").setup()
  vim.cmd("Mason " .. args.args)
end, { nargs = "*", desc = "Install language servers and tools" })

-- Only when its settings file exists, in the folder the plugin itself reads
-- (WAKATIME_HOME, else home); loaded half a second after the UI is up.
if vim.uv.fs_stat((vim.env.WAKATIME_HOME or vim.fn.expand "~") .. "/.wakatime.cfg") then
  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    callback = function()
      vim.defer_fn(function()
        vim.cmd.packadd "vim-wakatime"
      end, 500)
    end,
  })
end

require("explorer").setup()
require("statusline").setup()
require("snippets").setup()

return { missing_parsers = missing_parsers }
