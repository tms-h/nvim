local module_name = "configs.ocaml"
local ocaml = require(module_name)

-- Neovide can keep the module table cached while this config is edited.
-- Reload once if the cached version predates setup_indent.
if type(ocaml.setup_indent) ~= "function" then
  package.loaded[module_name] = nil
  ocaml = require(module_name)
end

if type(ocaml.setup_indent) == "function" then
  ocaml.setup_indent()
end
