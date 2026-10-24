# Sourced by shoot.sh: dump windows, buffers and messages, one shot.
R 'luaeval("vim.inspect({argv = vim.fn.argv(), cwd = vim.fn.getcwd(), bufs = vim.tbl_map(function(b) return vim.fn.bufname(b) end, vim.api.nvim_list_bufs())})")' >"$OUT/dump.txt"
R 'execute("messages")' >>"$OUT/dump.txt"
SHOT 0-start
