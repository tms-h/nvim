# Sourced by shoot.sh: Thomas's tab bar of 2026-11-22, ten tabs (fe-nvim's
# review pages beside the files they show), two tabpages, the current tab
# fe-nvim's diff of dune-project. Shot with the bar about 159 columns wide (his
# screenshot) and about 77 (his pane later). PROJECT_DIR should end in
# send-subscriptions/+share+ and hold bin/dune, bin/main.ml, lib/dune and
# lib/hyperliquid.mli, as janus's workspace does.
cat >"$OUT/tabs-setup.lua" <<EOF
local api, root = vim.api, "$PROJ"
local F = "janus/send-subscriptions"
local function page(name)
  local b = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(b, name)
  api.nvim_buf_set_lines(b, 0, -1, false, { name })
  vim.bo[b].buftype, vim.bo[b].modified = "nofile", false
  return b
end
local bufs = {
  page("fe://diff/" .. F .. " -- dune-project"),
  page("fe://feature/" .. F),
}
for _, file in ipairs { "bin/dune", "bin/main.ml", "lib/dune", "lib/hyperliquid.mli" } do
  bufs[#bufs + 1] = vim.fn.bufadd(root .. "/" .. file)
  vim.bo[bufs[#bufs]].buflisted = true
  bufs[#bufs + 1] = page("fe://review/" .. F .. " -- " .. file)
end
for i, b in ipairs(bufs) do
  require("tabs").place(b, i)
end
local start = api.nvim_get_current_buf()
api.nvim_win_set_buf(0, bufs[1])
api.nvim_buf_delete(start, { force = true })
vim.cmd("tab split | tabprevious")
EOF
R "execute('luafile $OUT/tabs-setup.lua')" >/dev/null
sleep 1
# Floating, sized to COLS columns, so the bar is COLS cells wide.
size() {
  local cols w
  inner hyprctl dispatch setfloating active >/dev/null
  w=$(inner hyprctl activewindow -j | jq '.size[0]')
  cols=$(L 'vim.o.columns')
  inner hyprctl dispatch resizeactive exact "$(awk -v w="$w" -v c="$cols" -v n="$1" 'BEGIN { printf "%d", (n + 0.5) * w / c }')" 400 >/dev/null
  inner hyprctl dispatch moveactive exact 20 20 >/dev/null
  sleep 1.5
  L 'vim.o.columns' >"$OUT/columns-$1.txt"
  L 'require("tabs").render()' >"$OUT/render-$1.txt"
}
size 159
SHOT tabs-159
size 77
SHOT tabs-77
