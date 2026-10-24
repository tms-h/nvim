return {
  cmd = { "ocamllsp" },
  filetypes = { "ocaml", "ocaml_interface", "ocamllex", "menhir", "dune" },
  -- The nearest dune project or opam file, else the repository root.
  root_dir = function(buf, on_dir)
    on_dir(vim.fs.root(buf, function(name)
      return name == "dune-project" or name == "dune-workspace" or name == "esy.json" or name:match "%.opam$" ~= nil
    end) or vim.fs.root(buf, ".git"))
  end,
}
