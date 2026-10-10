return {
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    lazy = false,
    config = function()
      local mc = require "multicursor-nvim"
      mc.setup()
      -- Restore the ordinary Escape mapping when the last cursor is cleared.
      mc.addKeymapLayer(function(set)
        set("n", "<Esc>", function()
          mc.clearCursors()
          vim.cmd.nohlsearch()
        end)
      end)
    end,
  },
}
