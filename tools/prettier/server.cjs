// Prettier kept loaded for Markdown saves (lua/lsp.lua). A fresh
// `prettier --stdin-filepath` run spends ~170 ms starting node and loading
// prettier before it formats; this process loads it once and then answers
// each save in a few ms.
//
// argv[2]: the prettier package folder (the one the `prettier` command runs).
// stdin: one JSON request per line, { id, text, filepath, cwd }.
// stdout: one JSON answer per line, { id, ok, text } (ok = false: the file
// stays as typed, as when the command exits non-zero).
//
// It does what the command does with --stdin-filepath FILE --prose-wrap
// preserve: a file matched by .gitignore or .prettierignore (in the cwd)
// comes back unchanged; options come from the file's prettier config and
// .editorconfig, read fresh for every save; --prose-wrap wins over them.
"use strict";
const path = require("path");
const readline = require("readline");
const prettier = require(process.argv[2]);

// Quit after 10 minutes without a request (~150 MB back); Neovim starts a
// new one when needed.
let idle;
function stayAlive() {
  clearTimeout(idle);
  idle = setTimeout(() => process.exit(0), 10 * 60 * 1000);
}
stayAlive();

async function format({ text, filepath, cwd }) {
  const file = path.resolve(cwd, filepath);
  const info = await prettier.getFileInfo(file, {
    ignorePath: [path.resolve(cwd, ".gitignore"), path.resolve(cwd, ".prettierignore")],
  });
  if (info.ignored) {
    return text;
  }
  await prettier.clearConfigCache();
  const config = await prettier.resolveConfig(file, { editorconfig: true });
  return prettier.format(text, { ...config, filepath: file, proseWrap: "preserve" });
}

// Load the Markdown printer now, so the first save does not wait for it.
const ready = prettier.format("# x\n", { parser: "markdown" }).catch(() => {});

readline.createInterface({ input: process.stdin }).on("line", async (line) => {
  stayAlive();
  await ready;
  let req;
  try {
    req = JSON.parse(line);
    const text = await format(req);
    process.stdout.write(JSON.stringify({ id: req.id, ok: true, text }) + "\n");
  } catch (err) {
    process.stdout.write(JSON.stringify({ id: req && req.id, ok: false, error: String(err) }) + "\n");
  }
});
// Neovim gone: stdin closes, and so does this.
process.stdin.on("end", () => process.exit(0));
