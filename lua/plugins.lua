-- The plugins, each for a job Neovim 0.12 does not do on its own. Managed by
-- the built-in vim.pack (:lua vim.pack.update() to update; versions are
-- pinned in nvim-pack-lock.json).
--
--   mini.nvim        finder (mini.pick), completion,
--                    key hints (mini.clue), TODO words (mini.hipatterns),
--                    git signs (mini.diff), icons, bracket pairs
--   nvim-tree.lua    the file tree
--   nvim-treesitter  installs the OCaml, Python, Rust... parsers
--   orgmode          README.org files (loaded on the first .org file)
--   mason.nvim       installs language servers (loaded by :Mason)
--   vim-wakatime     time tracking, when ~/.wakatime.cfg exists
local gh = function(repo)
  return "https://github.com/" .. repo
end
local later = function(plug)
  -- Install now, load when first needed (see the autocmds below).
  return { src = plug.src or plug, version = plug.version, data = { later = true } }
end

vim.pack.add({
  gh "nvim-mini/mini.nvim",
  gh "nvim-tree/nvim-tree.lua",
  { src = gh "nvim-treesitter/nvim-treesitter", version = "main" },
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
-- Docs and signatures show in one small float beside the menu.
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
-- TODO / FIXME / HACK / NOTE in comments: coloured words, never a filled
-- block (TodoText* in theme.lua). Outside a comment (a string, prose with
-- no tree-sitter comment) they stay plain, when tree-sitter can tell.
local function in_comment(buf, row, col)
  local ok, captures = pcall(vim.treesitter.get_captures_at_pos, buf, row, col)
  if not ok or #captures == 0 then
    return not pcall(vim.treesitter.get_parser, buf)
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

-- OCaml type variables ('a) and Rust lifetimes ('a) are not quotes.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "ocaml", "ocaml_interface", "rust" },
  callback = function(args)
    vim.keymap.set("i", "'", "'", { buffer = args.buf })
  end,
})

-- Key hints: pause after Space and the keys that can follow pop up in the
-- corner (like which-key).
local clue = require "mini.clue"
clue.setup {
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
  },
  window = { delay = 400, config = { width = "auto", border = "rounded" } },
}

-- The finder: set up on first use (finder.lua).
require("finder").setup()

-- ── Tree-sitter ────────────────────────────────────────────────────────────
-- Parsers this config needs beyond the ones Neovim ships (lua, markdown,
-- vimdoc, c, query). Installed once, in the background.
local parsers = { "ocaml", "ocaml_interface", "python", "rust", "toml", "json", "bash", "yaml" }
-- A language is installed only when its parser and its highlight queries both
-- load. The queries are links into the plugin's folder: renaming the data
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
  if #missing > 0 and vim.fn.executable "tree-sitter" == 1 then
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

if vim.uv.fs_stat(vim.fn.expand "~/.wakatime.cfg") then
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
