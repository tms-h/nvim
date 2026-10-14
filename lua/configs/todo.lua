-- Floating todo.md editor and an optional corner widget listing open items.
local M = {}

local todo_buf, todo_win = nil, nil
local widget_buf, widget_win = nil, nil
local widget_grp = vim.api.nvim_create_augroup("TodoWidget", { clear = true })
local widget_ns = vim.api.nvim_create_namespace "todo_widget"
local todo_ns = vim.api.nvim_create_namespace "todo_hl"
local widget_visible = false

vim.api.nvim_set_hl(0, "TodoWidgetNormal", { bg = "NONE" })
vim.api.nvim_set_hl(0, "TodoWidgetBorder", { fg = "#2d3538", bg = "NONE" })
vim.api.nvim_set_hl(0, "TodoWidgetHeading", { fg = "#b5db7a", bold = true })
vim.api.nvim_set_hl(0, "TodoWidgetOpen", { fg = "#e6dcc3" })
vim.api.nvim_set_hl(0, "TodoWidgetDone", { fg = "#5c6a72", strikethrough = true })
vim.api.nvim_set_hl(0, "TodoFloatNormal", { bg = "#0b0e0f" })
vim.api.nvim_set_hl(0, "TodoFloatBorder", { fg = "#363e3a", bg = "#0b0e0f" })
vim.api.nvim_set_hl(0, "TodoDesc", { fg = "#7a8478", italic = true })
vim.api.nvim_set_hl(0, "TodoDone", { fg = "#5c6a72", strikethrough = true })

local function todo_path()
  return vim.fn.getcwd() .. "/todo.md"
end

local function parse_headings(path)
  local f = io.open(path, "r")
  if not f then
    return { "  no todo.md" }, { "open" }
  end

  -- collect sections: each has a heading and a list of items
  local sections = {}
  local cur = nil
  for line in f:lines() do
    if line:match "^#+ " then
      cur = { heading = line:gsub("^#+ ", ""), items = {}, item_types = {} }
      sections[#sections + 1] = cur
    elseif cur then
      local cb, text = line:match "^%s*- %[([ x])%] (.+)"
      if cb then
        text = text:gsub(" %- .+$", ""):gsub(" — .+$", "")
        cur.items[#cur.items + 1] = { text = text, done = cb == "x" }
      end
    end
  end
  f:close()

  -- split into sections with open tasks vs all-done sections
  local active, done_secs = {}, {}
  for _, sec in ipairs(sections) do
    local has_open = false
    for _, item in ipairs(sec.items) do
      if not item.done then
        has_open = true
        break
      end
    end
    if has_open then
      active[#active + 1] = sec
    else
      done_secs[#done_secs + 1] = sec
    end
  end

  local lines, types = {}, {}

  -- show active sections first (only open tasks)
  for _, sec in ipairs(active) do
    if #lines > 0 then
      lines[#lines + 1] = ""
      types[#types + 1] = "blank"
    end
    lines[#lines + 1] = " " .. sec.heading
    types[#types + 1] = "heading"
    for _, item in ipairs(sec.items) do
      if not item.done then
        lines[#lines + 1] = " ○ " .. item.text
        types[#types + 1] = "open"
      end
    end
  end

  -- show completed sections as a single collapsed line each
  for _, sec in ipairs(done_secs) do
    if #lines > 0 then
      lines[#lines + 1] = ""
      types[#types + 1] = "blank"
    end
    lines[#lines + 1] = " ✓ " .. sec.heading
    types[#types + 1] = "done"
  end

  if #lines == 0 then
    return { "  all done!" }, { "done" }
  end
  return lines, types
end

local function refresh_widget()
  if not widget_visible then
    return
  end
  if todo_win and vim.api.nvim_win_is_valid(todo_win) then
    return
  end
  local ui = vim.api.nvim_list_uis()[1]
  if not ui then
    return
  end
  local lines, types = parse_headings(todo_path())
  local w = 38
  local h = math.min(#lines, 25)
  if not widget_buf or not vim.api.nvim_buf_is_valid(widget_buf) then
    widget_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[widget_buf].bufhidden = "hide"
  end
  vim.bo[widget_buf].modifiable = true
  vim.api.nvim_buf_set_lines(widget_buf, 0, -1, false, lines)
  vim.bo[widget_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(widget_buf, widget_ns, 0, -1)
  for i, t in ipairs(types) do
    local hl = t == "heading" and "TodoWidgetHeading"
      or t == "done" and "TodoWidgetDone"
      or t == "open" and "TodoWidgetOpen"
      or nil
    if hl then
      vim.api.nvim_buf_add_highlight(widget_buf, widget_ns, hl, i - 1, 0, -1)
    end
  end
  if widget_win and vim.api.nvim_win_is_valid(widget_win) then
    vim.api.nvim_win_set_config(widget_win, {
      relative = "editor",
      row = 1,
      col = ui.width - w - 2,
      width = w,
      height = h,
    })
  else
    widget_win = vim.api.nvim_open_win(widget_buf, false, {
      relative = "editor",
      row = 1,
      col = ui.width - w - 2,
      width = w,
      height = h,
      style = "minimal",
      border = "rounded",
      title = " todo ",
      title_pos = "center",
      focusable = false,
      zindex = 1,
    })
    vim.wo[widget_win].winblend = 25
    vim.wo[widget_win].winhighlight = "Normal:TodoWidgetNormal,FloatBorder:TodoWidgetBorder"
  end
end

local function close_widget()
  if widget_win and vim.api.nvim_win_is_valid(widget_win) then
    vim.api.nvim_win_close(widget_win, true)
    widget_win = nil
  end
end

local function toggle_widget()
  widget_visible = not widget_visible
  if widget_visible then
    refresh_widget()
  else
    close_widget()
  end
end

local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()
  local new = line:gsub("- %[ %]", "- [x]")
  if new == line then
    new = line:gsub("- %[x%]", "- [ ]")
  end
  if new ~= line then
    vim.api.nvim_set_current_line(new)
    vim.cmd "silent write!"
  end
end

local function toggle_todo()
  if todo_win and vim.api.nvim_win_is_valid(todo_win) then
    vim.api.nvim_win_close(todo_win, true)
    todo_win = nil
    refresh_widget()
    return
  end
  close_widget()
  local path = todo_path()
  if todo_buf and vim.api.nvim_buf_is_valid(todo_buf) then
    vim.api.nvim_buf_set_name(todo_buf, path)
  else
    todo_buf = vim.fn.bufnr(path, true)
    vim.bo[todo_buf].buflisted = false
  end
  vim.fn.bufload(todo_buf)
  vim.bo[todo_buf].filetype = "markdown"
  local ui = vim.api.nvim_list_uis()[1]
  local w = math.floor(ui.width * 0.6)
  local h = math.floor(ui.height * 0.6)
  todo_win = vim.api.nvim_open_win(todo_buf, true, {
    relative = "editor",
    row = math.floor((ui.height - h) / 2),
    col = math.floor((ui.width - w) / 2),
    width = w,
    height = h,
    style = "minimal",
    border = "rounded",
    title = " todo ",
    title_pos = "center",
  })
  vim.wo[todo_win].winblend = 10
  vim.wo[todo_win].wrap = true
  vim.wo[todo_win].linebreak = true
  vim.wo[todo_win].breakindent = true
  vim.wo[todo_win].breakindentopt = "shift:6"
  vim.wo[todo_win].winhighlight = "Normal:TodoFloatNormal,FloatBorder:TodoFloatBorder"
  vim.schedule(function()
    pcall(function()
      vim.cmd "RenderMarkdown buf_disable"
    end)
  end)
  local function apply_todo_hl()
    if not todo_buf or not vim.api.nvim_buf_is_valid(todo_buf) then
      return
    end
    vim.api.nvim_buf_clear_namespace(todo_buf, todo_ns, 0, -1)
    for i, line in ipairs(vim.api.nvim_buf_get_lines(todo_buf, 0, -1, false)) do
      if line:match "^%s*- %[x%]" then
        vim.api.nvim_buf_add_highlight(todo_buf, todo_ns, "TodoDone", i - 1, 0, -1)
      else
        local pos = line:find(" — ", 7) or line:find(" %- ", 7)
        if pos then
          vim.api.nvim_buf_add_highlight(todo_buf, todo_ns, "TodoDesc", i - 1, pos - 1, -1)
        end
      end
    end
  end
  apply_todo_hl()
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = widget_grp,
    buffer = todo_buf,
    callback = function()
      vim.schedule(apply_todo_hl)
    end,
  })
  vim.keymap.set("n", "q", toggle_todo, { buffer = todo_buf })
  vim.keymap.set("n", "<CR>", toggle_checkbox, { buffer = todo_buf })
  vim.keymap.set("n", "o", function()
    local line = vim.api.nvim_get_current_line()
    local prefix = line:match "^(%s*- %[[ x]%] )" or ""
    if prefix ~= "" then
      prefix = prefix:gsub("%[x%]", "[ ]")
    end
    vim.cmd "normal! o"
    if prefix ~= "" then
      vim.api.nvim_set_current_line(prefix)
      vim.cmd "startinsert!"
    else
      vim.cmd "startinsert"
    end
  end, { buffer = todo_buf })
  vim.keymap.set("i", "<CR>", function()
    local line = vim.api.nvim_get_current_line()
    local prefix = line:match "^(%s*- %[[ x]%] )"
    if prefix then
      prefix = prefix:gsub("%[x%]", "[ ]")
      return "<CR>" .. prefix
    end
    return "<CR>"
  end, { buffer = todo_buf, expr = true })
end

vim.api.nvim_create_autocmd("BufWritePost", {
  group = widget_grp,
  pattern = "todo.md",
  callback = function()
    vim.schedule(refresh_widget)
  end,
})
vim.api.nvim_create_autocmd("VimResized", {
  group = widget_grp,
  callback = function()
    if widget_visible then
      vim.schedule(refresh_widget)
    end
  end,
})
vim.api.nvim_create_autocmd("VimEnter", {
  group = widget_grp,
  once = true,
  callback = function()
    vim.defer_fn(refresh_widget, 100)
  end,
})

M.toggle = toggle_todo
M.toggle_widget = toggle_widget

return M
