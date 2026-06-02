return {
  {
    "xeluxee/competitest.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    cmd = "CompetiTest",
    opts = {
      template_file = vim.fn.expand("~/cp/templates/template.cpp"),
      testcases_use_single_file = true,
      compile_command = {
        cpp = {
          exec = "g++-15",
          args = {
            "-std=c++20", "-Wall", "-Wextra", "-fsanitize=address,undefined",
            "$(FNAME)", "-o", "$(FNOEXT)",
          },
        },
      },
    },
  },
}
