-- Standalone colorscheme matching IntelliJ IDEA's actual default Darcula
-- theme. Self-contained (not layered on top of another plugin/colorscheme
-- via an autocmd) so there's no dependency on load order — `highlight
-- clear` runs here, then every group needed is set directly in one place.
--
-- Base UI chrome below is adapted from brargenzilian/darcula-solid.nvim;
-- syntax colors (keywords, strings, numbers, types, fields, methods,
-- annotations, selection) are IntelliJ's documented default Darcula
-- palette, not eyeballed from a screenshot.

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
  vim.cmd("syntax reset")
end
vim.cmd("set t_Co=256")
vim.g.colors_name = "darcula-intellij"

local c = {
  bg = "#2b2b2b",
  ui_bg = "#3c3f41",
  fg = "#a9b7c6",
  cursor = "#bbbbbb",
  selection = "#214283",
  keyword = "#cc7832",
  string = "#6a8759",
  number = "#6897bb",
  comment = "#808080",
  annotation = "#bbb529",
  field = "#9876aa",
  method = "#ffc66d",
  gray = "#585e65",
  lightgray = "#8a8a8a",
  subtle_black = "#313235",
  red = "#e74946",
  blue = "#83b1f1",
  magenta = "#d194c7",
  green = "#8ca664",
  yellow = "#ffc66b",
}

local hl = vim.api.nvim_set_hl

-- Base editor chrome
hl(0, "Normal", { fg = c.fg, bg = c.bg })
hl(0, "NormalNC", { link = "Normal" })
hl(0, "NormalFloat", { fg = c.fg, bg = c.bg })
hl(0, "FloatBorder", { fg = c.lightgray, bg = c.bg })
hl(0, "FloatTitle", { fg = c.fg, bg = c.bg, bold = true })
hl(0, "Cursor", { fg = c.bg, bg = c.cursor })
hl(0, "CursorIM", { link = "Cursor" })
hl(0, "TermCursor", { link = "Cursor" })
hl(0, "Visual", { bg = c.selection })
hl(0, "VisualNOS", { link = "Visual" })
hl(0, "Search", { fg = "#f7f7f7", bg = c.selection })
hl(0, "IncSearch", { link = "Search" })
hl(0, "CurSearch", { link = "Search" })
hl(0, "Pmenu", { fg = c.fg, bg = c.ui_bg })
hl(0, "PmenuSel", { bg = c.selection, bold = true })
hl(0, "PmenuSbar", { bg = c.ui_bg })
hl(0, "PmenuThumb", { bg = c.gray })
hl(0, "StatusLine", { bg = c.ui_bg })
hl(0, "StatusLineNC", { link = "StatusLine" })
hl(0, "WinSeparator", { fg = c.lightgray, bg = c.bg })
hl(0, "VertSplit", { link = "WinSeparator" })
hl(0, "CursorLine", { bg = c.ui_bg })
hl(0, "CursorLineNr", { fg = c.keyword })
hl(0, "ColorColumn", { bg = c.ui_bg })
hl(0, "LineNr", { fg = c.gray })
hl(0, "SignColumn", { link = "LineNr" })
hl(0, "FoldColumn", { fg = c.gray })
hl(0, "Folded", { fg = c.lightgray, bg = c.subtle_black })
hl(0, "MatchParen", { fg = "#f7f7f7", bg = c.subtle_black })
-- LSP document highlight: other occurrences of the word under cursor.
-- `highlight clear` above wipes these, and nothing else in this file was
-- redefining them, so the feature fired but rendered invisibly.
hl(0, "LspReferenceText", { bg = c.subtle_black })
hl(0, "LspReferenceRead", { bg = c.subtle_black })
hl(0, "LspReferenceWrite", { bg = c.subtle_black, underline = true })
hl(0, "NonText", { fg = c.fg, bg = c.bg })
hl(0, "Whitespace", { fg = c.gray })
hl(0, "Conceal", { fg = c.gray })
hl(0, "EndOfBuffer", { link = "Conceal" })

-- Diagnostics
hl(0, "DiagnosticError", { fg = c.red })
hl(0, "DiagnosticWarn", { fg = c.yellow })
hl(0, "DiagnosticInfo", { fg = c.blue })
hl(0, "DiagnosticHint", { fg = c.blue })
hl(0, "DiagnosticOk", { fg = c.green })
hl(0, "DiagnosticUnderlineError", { sp = c.red, undercurl = true })
hl(0, "DiagnosticUnderlineWarn", { sp = c.yellow, undercurl = true })
hl(0, "DiagnosticUnderlineInfo", { sp = c.blue, undercurl = true })
hl(0, "DiagnosticUnderlineHint", { sp = c.blue, undercurl = true })
hl(0, "DiffAdd", { bg = "#32583c" })
hl(0, "DiffChange", { bg = "#514f39" })
hl(0, "DiffDelete", { bg = c.red })
hl(0, "DiffText", { bg = "#27333f" })

-- Legacy syntax groups (fallback when treesitter isn't active)
hl(0, "Comment", { fg = c.comment, italic = true })
hl(0, "String", { fg = c.string })
hl(0, "Number", { fg = c.number })
hl(0, "Boolean", { link = "Number" })
hl(0, "Float", { link = "Number" })
hl(0, "Constant", { fg = c.keyword })
hl(0, "Keyword", { fg = c.keyword })
hl(0, "Statement", { link = "Keyword" })
hl(0, "Conditional", { link = "Keyword" })
hl(0, "Repeat", { link = "Keyword" })
hl(0, "Label", { link = "Keyword" })
hl(0, "PreProc", { link = "Keyword" })
hl(0, "Type", { fg = c.fg })
hl(0, "Typedef", { link = "Type" })
hl(0, "StorageClass", { fg = c.magenta })
hl(0, "Structure", { link = "StorageClass" })
hl(0, "Identifier", { fg = c.fg })
hl(0, "Function", { fg = c.method })
hl(0, "Operator", { fg = c.fg })
hl(0, "Delimiter", { fg = c.fg })
hl(0, "Special", { fg = c.fg })
hl(0, "SpecialChar", { fg = c.keyword })
hl(0, "Underlined", { underline = true })
hl(0, "Todo", { bold = true, fg = c.yellow })
hl(0, "Error", { fg = c.red })

-- Treesitter captures — what actually renders in modern buffers.
hl(0, "@type", { fg = c.fg })
hl(0, "@type.builtin", { fg = c.keyword })
hl(0, "@variable", { fg = c.fg })
hl(0, "@variable.builtin", { fg = c.keyword })
hl(0, "@variable.parameter", { fg = c.fg })
hl(0, "@variable.member", { fg = c.field })
hl(0, "@property", { fg = c.field })
hl(0, "@field", { fg = c.field })
hl(0, "@function", { fg = c.method })
hl(0, "@function.method", { fg = c.method })
hl(0, "@function.method.call", { fg = c.method })
hl(0, "@function.call", { fg = c.method })
hl(0, "@function.builtin", { fg = c.method })
hl(0, "@constructor", { fg = c.fg })
hl(0, "@string", { fg = c.string })
hl(0, "@number", { fg = c.number })
hl(0, "@boolean", { fg = c.number })
hl(0, "@keyword", { fg = c.keyword })
hl(0, "@keyword.function", { fg = c.keyword })
hl(0, "@keyword.return", { fg = c.keyword })
hl(0, "@keyword.modifier", { fg = c.keyword })
hl(0, "@keyword.type", { fg = c.keyword })
hl(0, "@keyword.import", { fg = c.keyword })
hl(0, "@keyword.conditional", { fg = c.keyword })
hl(0, "@keyword.repeat", { fg = c.keyword })
hl(0, "@keyword.exception", { fg = c.keyword })
hl(0, "@keyword.operator", { fg = c.keyword })
hl(0, "@comment", { fg = c.comment, italic = true })
hl(0, "@operator", { fg = c.fg })
hl(0, "@punctuation.bracket", { fg = c.fg })
hl(0, "@punctuation.delimiter", { fg = c.fg })
-- Annotations (@NotNull, @Component, ...): distinct muted olive-yellow,
-- not the same gold used for method names.
hl(0, "@attribute", { fg = c.annotation })

-- jdtls (and most LSPs) send semantic tokens for keywords/modifiers/types,
-- which take priority over the plain treesitter captures above — so every
-- `@lsp.type.*`/`@lsp.mod.*` group needs its own explicit value too,
-- otherwise it silently keeps whatever the PREVIOUS colorscheme (tokyonight,
-- always loaded first at startup) had left set for that group. Mirrors the
-- treesitter mapping above 1:1.
hl(0, "@lsp.type.class", { fg = c.fg })
hl(0, "@lsp.type.decorator", { fg = c.annotation })
hl(0, "@lsp.type.enum", { fg = c.fg })
hl(0, "@lsp.type.enumMember", { fg = c.field })
hl(0, "@lsp.type.event", { fg = c.fg })
hl(0, "@lsp.type.function", { fg = c.method })
hl(0, "@lsp.type.interface", { fg = c.fg })
hl(0, "@lsp.type.keyword", { fg = c.keyword })
hl(0, "@lsp.type.macro", { fg = c.keyword })
hl(0, "@lsp.type.method", { fg = c.method })
hl(0, "@lsp.type.modifier", { fg = c.keyword })
hl(0, "@lsp.type.modifier.java", { fg = c.keyword })
hl(0, "@lsp.type.namespace", { fg = c.fg })
hl(0, "@lsp.type.number", { fg = c.number })
hl(0, "@lsp.type.operator", { fg = c.fg })
hl(0, "@lsp.type.parameter", { fg = c.fg })
hl(0, "@lsp.type.property", { fg = c.field })
hl(0, "@lsp.type.regexp", { fg = c.string })
hl(0, "@lsp.type.string", { fg = c.string })
hl(0, "@lsp.type.struct", { fg = c.fg })
hl(0, "@lsp.type.type", { fg = c.fg })
hl(0, "@lsp.type.typeParameter", { fg = c.fg })
hl(0, "@lsp.type.variable", { fg = c.fg })
