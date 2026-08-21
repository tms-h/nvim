local plugin_dir = vim.env.HOOT_NVIM_DIR or vim.fn.expand "~/Desktop/Projects/hoot.nvim"

-- Hoot is a local, optional plugin. Keep the shared config loadable on machines
-- where Thomas's development checkout is absent.
if vim.fn.isdirectory(plugin_dir) ~= 1 then
  return {}
end

return {
  {
    "hoot.nvim",
    dir = plugin_dir,
    event = "VeryLazy",
    opts = {
      enabled = false,
      api_key_file = "~/.config/gemini/key",
    },
    keys = {
      { "<leader>h", "<cmd>HootHint<cr>", desc = "hoot: hint me" },
    },
  },
}
