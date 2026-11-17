-- OCaml snippets that expand as you type, from the old config: on a line of
-- its own, `mod_board` then Space becomes `module Board = struct ... end`;
-- likewise rec_, test_, expect_, qc_, record_, variant_, type_ and orerror_.
-- `der` then Space, on a line of its own or ending a `type` line, becomes
-- `[@@deriving sexp, compare, equal]` with the list selected: type to replace
-- it, Tab to keep it. Tab / Shift+Tab move through the fields (vim.snippet).
-- Space o s lists them all (Tab previews, Enter types the trigger below).
-- Also auto-brackets: accepting a function or method from the completion
-- menu adds "()" with the cursor inside (not in OCaml, where functions take
-- no brackets).
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

local DERIVING = "[@@deriving ${1:sexp, compare, equal}]$0"

-- Every snippet, in the order Space o s lists them: the trigger, an example
-- name, and the body (LSP snippet syntax) for the captured name.
local OCAML = {
  {
    trigger = "der",
    example = "",
    body = function()
      return DERIVING
    end,
  },
  {
    trigger = "mod_",
    example = "board",
    body = function(n)
      return "module " .. pascal(n) .. " = struct\n\t$0\nend"
    end,
  },
  {
    trigger = "rec_",
    example = "walk",
    body = function(n)
      return "let rec " .. n .. " ${1:arg} =\n\t$0"
    end,
  },
  {
    trigger = "test_",
    example = "adds_up",
    body = function(n)
      return 'let%test "' .. title(n) .. '" =\n\t${0:true}'
    end,
  },
  {
    -- Prints with print_s, the Jane Street default, so the test reads the value
    -- as a sexp; the [%expect] block starts empty for Space o p to promote.
    trigger = "expect_",
    example = "prints_book",
    body = function(n)
      return 'let%expect_test "'
        .. title(n)
        .. '" =\n\tprint_s [%sexp (${1:value} : ${2:t})];\n\t[%expect {|$0|\\}]'
    end,
  },
  {
    -- A property test: type the input type once (the generator and the printer
    -- share it), then the property.
    trigger = "qc_",
    example = "round_trips",
    body = function(n)
      return 'let%test_unit "'
        .. title(n)
        .. '" =\n\tQuickcheck.test\n\t\t[%quickcheck.generator: ${1:int list}]\n\t\t~sexp_of:[%sexp_of: $1]\n\t\t~f:(fun ${2:x} -> [%test_result: ${3:int list}] ${4:got} ~expect:${0:want})'
    end,
  },
  {
    trigger = "record_",
    example = "order",
    body = function(n)
      return "type " .. n .. " =\n\t{ ${1:field} : ${2:type}\n\t}\n[@@deriving ${3:sexp, compare, equal}]$0"
    end,
  },
  {
    trigger = "variant_",
    example = "side",
    body = function(n)
      return "type " .. n .. " =\n\t| ${1:A}\n\t| ${2:B}\n[@@deriving ${3:sexp, compare, equal}]$0"
    end,
  },
  {
    trigger = "type_",
    example = "price",
    body = function(n)
      return "type " .. n .. " = ${1:int} [@@deriving ${2:sexp, compare, equal}]$0"
    end,
  },
  {
    trigger = "orerror_",
    example = "parse",
    body = function(n)
      return "let " .. n .. ' ${1:arg} : ${2:unit} Or_error.t =\n\t${0:Or_error.error_string "TODO"}'
    end,
  },
}

local BY_PREFIX = {}
for _, s in ipairs(OCAML) do
  BY_PREFIX[s.trigger] = s.body
end

---`der ` alone on a line, or ending a `type` line. Not after `and`, `|` or
---`}`: those also start let-and bindings, match arms and record expressions,
---where `der` is code. Returns the column where `der` starts, or nil.
local function deriving_start(before)
  local head = before:match "^(.-)der $"
  if not head then
    return nil
  end
  local own_line = head:match "^%s*$"
  local ends_type = head:match "^%s*type%s.*%s$"
  return (own_line or ends_type) and #head or nil
end

---Expand a trigger that ends right before the cursor, if there is one.
---Returns nothing: an autocmd whose callback returns true is deleted, which
---left a buffer with no snippets after its first one.
function M.try_expand()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local before, after = line:sub(1, col), line:sub(col + 1)
  if vim.trim(after) ~= "" then
    return
  end
  local start, body = deriving_start(before), DERIVING
  if not start then
    local indent, prefix, name = before:match "^(%s*)(%a+_)(%a[%w_]*) $"
    if not (prefix and BY_PREFIX[prefix]) then
      return
    end
    start, body = #indent, BY_PREFIX[prefix](name)
  end
  api.nvim_buf_set_text(0, row - 1, start, row - 1, col, {})
  api.nvim_win_set_cursor(0, { row, start })
  vim.snippet.expand(body)
end

---A snippet body as the text it expands to: fields show their defaults.
local function plain(body)
  local text = body:gsub("%${%d+:([^}]*)}", "%1"):gsub("%$%d+", ""):gsub("\\}", "}"):gsub("\t", "  ")
  return vim.split(text, "\n")
end

---Space o s: every snippet with what it expands to. Tab previews the whole
---expansion; Enter types the trigger on a new line below, ready for the name.
function M.pick()
  local items = {}
  for _, s in ipairs(OCAML) do
    local lines = plain(s.body(s.example))
    local shown = s.trigger == "der" and "der" or s.trigger .. s.example
    table.insert(items, {
      text = string.format("%-20s %s%s", shown, lines[1], #lines > 1 and " …" or ""),
      trigger = s.trigger == "der" and "der " or s.trigger,
      lines = lines,
    })
  end
  local pick = require("finder").load()
  pick.start {
    source = {
      name = "OCaml snippets (type the trigger, then Space)",
      items = items,
      -- Colour only: filetype=ocaml would run the OCaml setup (ocp-indent,
      -- keys, ruler, ocamllsp) on this scratch buffer and the picker window.
      preview = function(buf, item)
        api.nvim_buf_set_lines(buf, 0, -1, false, item.lines)
        pcall(vim.treesitter.start, buf, "ocaml")
      end,
      choose = function(item)
        vim.schedule(function()
          api.nvim_feedkeys("o" .. item.trigger, "n", false)
        end)
      end,
    },
  }
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
