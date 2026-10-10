local luasnip = require "luasnip"

local snippet = luasnip.snippet
local text = luasnip.text_node
local insert = luasnip.insert_node
local func = luasnip.function_node

local function captured_identifier(_, snip)
  return snip.captures[1] or "name"
end

local function captured_title(_, snip)
  return (snip.captures[1] or "name"):gsub("_", " ")
end

local function pascal_case(_, snip)
  local words = vim.split(snip.captures[1] or "module", "_", { plain = true, trimempty = true })
  for index, word in ipairs(words) do
    words[index] = word:sub(1, 1):upper() .. word:sub(2)
  end
  return table.concat(words)
end

local function standalone_named_trigger(prefix)
  return function(line_to_cursor)
    return line_to_cursor:match("^%s*" .. prefix .. "[%a][%w_]*%s$") ~= nil
  end
end

local function named_auto(prefix, name, description, nodes)
  return snippet({
    trig = prefix .. "([%a][%w_]*)%s",
    trigEngine = "pattern",
    name = name,
    dscr = description,
    wordTrig = true,
    hidden = true,
    condition = standalone_named_trigger(prefix),
  }, nodes)
end

local hints = {
  snippet({
    trig = "mod_",
    name = "Named module",
    dscr = "Hint: mod_board then Space creates module Board = struct",
  }, {
    text "module ",
    insert(1, "Name"),
    text { " = struct", "  " },
    insert(0),
    text { "", "end" },
  }),

  snippet({
    trig = "rec_",
    name = "Named recursive function",
    dscr = "Hint: rec_loop then Space creates let rec loop arg = ...",
  }, {
    text "let rec ",
    insert(1, "name"),
    text " ",
    insert(2, "arg"),
    text { " =", "  " },
    insert(0),
  }),

  snippet({
    trig = "test_",
    name = "Jane Street inline test",
    dscr = "Hint: test_name then Space creates let%test (requires PPX)",
  }, {
    text 'let%test "',
    insert(1, "name"),
    text { '" =', "  " },
    insert(0, "true"),
  }),

  snippet({
    trig = "expect_",
    name = "Jane Street expect test",
    dscr = "Hint: expect_name then Space creates let%expect_test (requires PPX)",
  }, {
    text 'let%expect_test "',
    insert(1, "name"),
    text { '" =', "  " },
    insert(2, 'print_endline "TODO"'),
    text { ";", "  [%expect {|", "    " },
    insert(0, "TODO"),
    text { "", "  |}]" },
  }),

  snippet({
    trig = "record_",
    name = "Record with common deriving helpers",
    dscr = "Hint: record_order then Space creates a record with sexp, compare, equal",
  }, {
    text "type ",
    insert(1, "name"),
    text { " =", "  { " },
    insert(2, "field"),
    text " : ",
    insert(3, "type"),
    text { "", "  }", "[@@deriving sexp, compare, equal]" },
    insert(0),
  }),

  snippet({
    trig = "orerror_",
    name = "Named Or_error function",
    dscr = "Hint: orerror_parse then Space creates a function returning Or_error.t",
  }, {
    text "let ",
    insert(1, "name"),
    text " ",
    insert(2, "arg"),
    text " : ",
    insert(3, "unit"),
    text { " Or_error.t =", "  " },
    insert(0, 'Or_error.error_string "TODO"'),
  }),
}

local autos = {
  named_auto("mod_", "Named OCaml module", "Expand mod_name into an OCaml module struct", {
    text "module ",
    func(pascal_case),
    text { " = struct", "  " },
    insert(0),
    text { "", "end" },
  }),

  named_auto("rec_", "Named recursive function", "Expand rec_name into a recursive function", {
    text "let rec ",
    func(captured_identifier),
    text " ",
    insert(1, "arg"),
    text { " =", "  " },
    insert(0),
  }),

  named_auto("test_", "Named inline test", "Expand test_name into a Jane Street inline test", {
    text 'let%test "',
    func(captured_title),
    text { '" =', "  " },
    insert(0, "true"),
  }),

  named_auto("expect_", "Named expect test", "Expand expect_name into a Jane Street expect test", {
    text 'let%expect_test "',
    func(captured_title),
    text { '" =', "  " },
    insert(1, 'print_endline "TODO"'),
    text { ";", "  [%expect {|", "    " },
    insert(0, "TODO"),
    text { "", "  |}]" },
  }),

  named_auto("record_", "Named record type", "Expand record_name into a record with deriving helpers", {
    text "type ",
    func(captured_identifier),
    text { " =", "  { " },
    insert(1, "field"),
    text " : ",
    insert(2, "type"),
    text { "", "  }", "[@@deriving sexp, compare, equal]" },
    insert(0),
  }),

  named_auto("orerror_", "Named Or_error function", "Expand orerror_name into a function returning Or_error.t", {
    text "let ",
    func(captured_identifier),
    text " ",
    insert(1, "arg"),
    text " : ",
    insert(2, "unit"),
    text { " Or_error.t =", "  " },
    insert(0, 'Or_error.error_string "TODO"'),
  }),
}

return hints, autos
