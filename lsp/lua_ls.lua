return {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { ".luarc.json", ".stylua.toml", "stylua.toml", ".git" },
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
      telemetry = { enable = false },
    },
  },
}
