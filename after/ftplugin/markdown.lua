-- Markdown always soft-wraps at word boundaries, with wrapped lines indented
-- like their first line. A file with a pipe table wraps too: a table row that
-- runs off the right edge hides the rest of the row, which is worse than a
-- wrapped row.
vim.wo[0][0].wrap = true
vim.wo[0][0].linebreak = true
vim.wo[0][0].breakindent = true
