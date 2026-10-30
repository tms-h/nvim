-- OCaml snippets that expand as you type, from the old config: on a line of
-- its own, `mod_board` then Space becomes `module Board = struct ... end`;
-- likewise rec_, test_, expect_, record_ and orerror_. Tab / Shift+Tab move
-- through the fields (vim.snippet). Also auto-brackets: accepting a
-- function or method from the completion menu adds "()" with the cursor
-- inside (not in OCaml, where functions take no brackets).
local M = {}

local api = vim.api

local function pascal(name)
  return (name:gsub("_?(%w)(%w*)", function(first, rest)
    return first:upper() .. rest
  end))
end

local function title(name)
  return (name:gsub("_", " "))
end

-- prefix -> body (LSP snippet syntax) for the captured name.
M.OCAML = {
  mod_ = function(n)
    return "module " .. pascal(n) .. " = struct\n\t$0\nend"
  end,
  rec_ = function(n)
    return "let rec " .. n .. " ${1:arg} =\n\t$0"
  end,
  test_ = function(n)
    return 'let%test "' .. title(n) .. '" =\n\t${0:true}'
  end,
  expect_ = function(n)
    return 'let%expect_test "' .. title(n) .. '" =\n\t${1:print_endline "TODO"};\n\t[%expect {|\n\t\t${0:TODO}\n\t|\\}]'
  end,
  record_ = function(n)
    return "type " .. n .. " =\n\t{ ${1:field} : ${2:type}\n\t}\n[@@deriving sexp, compare, equal]$0"
  end,
  orerror_ = function(n)
    return "let " .. n .. ' ${1:arg} : ${2:unit} Or_error.t =\n\t${0:Or_error.error_string "TODO"}'
  end,
}

---Expand a trigger that ends right before the cursor, if there is one.
---Returns nothing: an autocmd whose callback returns true is deleted, which
---left a buffer with no snippets after its first one.
function M.try_expand()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local before, after = line:sub(1, col), line:sub(col + 1)
  local indent, prefix, name = before:match "^(%s*)(%a+_)([%a][%w_]*) $"
  local body = prefix and M.OCAML[prefix]
  if not body or vim.trim(after) ~= "" then
    return
  end
  api.nvim_buf_set_text(0, row - 1, #indent, row - 1, col, {})
  api.nvim_win_set_cursor(0, { row, #indent })
  vim.snippet.expand(body(name))
end

local BRACKETS = { python = true, rust = true, lua = true }
local CALLABLE = { Function = true, Method = true }

---After a completion: add "()" behind a function or method, cursor inside.
function M.auto_brackets(item)
  if not BRACKETS[vim.bo.filetype] or type(item) ~= "table" or not CALLABLE[item.kind or ""] then
    return
  end
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local next_char = line:sub(col + 1, col + 1)
  if next_char == "(" or line:sub(col, col) == ")" or line:sub(1, col):find "%(%s*$" then
    return
  end
  api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { "()" })
  api.nvim_win_set_cursor(0, { row, col + 1 })
end

function M.setup()
  local group = api.nvim_create_augroup("Snippets", { clear = true })
  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "ocaml",
    callback = function(args)
      api.nvim_create_autocmd("TextChangedI", { group = group, buffer = args.buf, callback = M.try_expand })
    end,
  })
  api.nvim_create_autocmd("CompleteDone", {
    group = group,
    callback = function()
      if vim.v.event.reason == "accept" then
        M.auto_brackets(vim.v.completed_item)
      end
    end,
  })
end

return M
