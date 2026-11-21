return {
  cmd = { "ocamllsp" },
  filetypes = { "ocaml", "ocaml_interface", "ocamllex", "menhir", "dune" },
  -- Code lens: each top-level let's inferred type above it (off by default).
  settings = { codelens = { enable = true } },
  -- The nearest dune project or opam file, else the repository root. Not
  -- the ~/.opam folder: it made ~ the root of a file outside any project,
  -- and that server heard every dune build under ~.
  root_dir = function(buf, on_dir)
    on_dir(vim.fs.root(buf, function(name)
      return name == "dune-project" or name == "dune-workspace" or name == "esy.json" or name:match "^.+%.opam$" ~= nil
    end) or vim.fs.root(buf, ".git"))
  end,
}
