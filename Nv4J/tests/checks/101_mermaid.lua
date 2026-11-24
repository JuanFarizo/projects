-- :Nv4JMermaid (specs/features/mermaid.md): pure, nothing downloaded, no real file touched (dir stubbed to /tmp/nv4j/d101-<pid>).
--  targets    : this machine has a release target and a pinned 64-hex SHA-256 for it; all four targets are pinned.
--  shim_args  : the generated `mmdc` shim turns snacks' flags (-i -o -b -t -s) into `mmdr -i -o -e png -t` (a fake mmdr records them).
--  path_setup : setup() puts the dir first on PATH only when mmdr and mmdc exist there; vim.g.nv4j_mermaid = false or missing files = no change.
--  toggle_safe : <leader>cm never errors; nil + buffer untouched when snacks.image is off, a count + flag when on.
--  not_installed : with the dir absent, installed() is false and setup() leaves PATH alone.
local lsp = require("lsp")
local P = "101_mermaid."
local function rep(name, ok, detail) lsp.report(P .. name, ok and true or false, detail) end
local M = require("nv4j.mermaid")
local TMP = "/tmp/nv4j/d101-" .. vim.fn.getpid()
vim.fn.delete(TMP, "rf")
vim.fn.mkdir(TMP, "p")

local t = M.target()
local n = 0
for _, s in pairs(M.SHA) do if s:match("^%x+$") and #s == 64 then n = n + 1 end end
rep("targets", t ~= nil and M.SHA[t] ~= nil and n == 4, "target=" .. tostring(t) .. " pinned=" .. n)

local real_dir, real_path, real_flag = M.dir, vim.env.PATH, vim.g.nv4j_mermaid
M.dir = function() return TMP .. "/m" end
rep("not_installed", not M.installed() and (function() M.setup(); return vim.env.PATH == real_path end)(), "PATH changed with no install")

vim.fn.mkdir(TMP .. "/m", "p")
local f = assert(io.open(TMP .. "/m/mmdc", "w")); f:write(M.SHIM); f:close()
f = assert(io.open(TMP .. "/m/mmdr", "w")); f:write('#!/bin/sh\necho "$@" > "' .. TMP .. '/args"\n'); f:close()
vim.uv.fs_chmod(TMP .. "/m/mmdc", tonumber("755", 8))
vim.uv.fs_chmod(TMP .. "/m/mmdr", tonumber("755", 8))
local r = vim.system({ TMP .. "/m/mmdc", "-i", "a.mmd", "-o", "b.png", "-b", "transparent", "-t", "dark", "-s", "2" }):wait()
local args = vim.trim(table.concat(vim.fn.readfile(TMP .. "/args"), " "))
rep("shim_args", r.code == 0 and args == "-i a.mmd -o b.png -e png -t dark", "exit=" .. r.code .. " args=" .. args)

vim.g.nv4j_mermaid = false
M.setup()
local off_ok = vim.env.PATH == real_path
vim.g.nv4j_mermaid = nil
M.setup()
local on_ok = vim.startswith(vim.env.PATH, TMP .. "/m:")
rep("path_setup", off_ok and on_ok, "flag off unchanged=" .. tostring(off_ok) .. " on first=" .. tostring(on_ok))

vim.env.PATH, M.dir, vim.g.nv4j_mermaid = real_path, real_dir, real_flag
vim.fn.delete(TMP, "rf")

-- toggle_safe : <leader>cm never errors: it returns nil (and leaves the buffer alone) when snacks.image is off, or a diagram count and flips the buffer flag when it is on.
do
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(b)
  local ok, n = pcall(M.toggle)
  local flag = vim.b[b].nv4j_mermaid_hide
  rep("toggle_safe", ok and ((n == nil and flag == nil) or (type(n) == "number" and flag == true)), "ok=" .. tostring(ok) .. " ret=" .. tostring(n) .. " hide=" .. tostring(flag))
end

lsp.finish()
