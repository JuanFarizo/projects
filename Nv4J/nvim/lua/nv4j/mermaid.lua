-- Mermaid diagrams inside Neovim (specs/features/mermaid.md). POC, opt-in, one directory to delete.
--
-- snacks.image (already in LazyVim) draws ```mermaid blocks in markdown, but converts them by running
-- `mmdc` (mermaid-cli: Node + Chromium, seconds per diagram). This module installs `mmdr`
-- (github.com/1jehuang/mermaid-rs-renderer: one 3 MB native binary, no browser, ~0.2 s) into
-- <data>/mermaid/ plus a 5-line `mmdc` shim that maps snacks' flags to mmdr, and puts that directory
-- first on PATH only when it exists. Nothing is installed or changed until `:Nv4JMermaid install`.
--   :Nv4JMermaid install   download the pinned mmdr for this OS/CPU, check its SHA-256, write the shim
--   :Nv4JMermaid remove    delete the directory (rollback; a restart drops the PATH entry)
--   :Nv4JMermaid status
local M = {}

M.VERSION = "v0.3.1"
local BASE = "https://github.com/1jehuang/mermaid-rs-renderer/releases/download/" .. M.VERSION .. "/mmdr-"
-- target triple -> SHA-256 of the release tarball (computed 2026-11-16 from the GitHub release assets)
M.SHA = {
  ["aarch64-apple-darwin"] = "562d0250cb8588adefe398a23e4bbdf67f242849ea8d888c38268bcc3edf3223",
  ["x86_64-apple-darwin"] = "ad035258822b60ee6bb3c086c3c7325dafe314bfab16a3bb99d692c18fad59cd",
  ["x86_64-unknown-linux-gnu"] = "e1da47b758769bff21b82a480fad640a3b893a90fc0dc321551486f8b50c7200",
  ["aarch64-unknown-linux-gnu"] = "a74a121a2dd3bc8d30c17c954b3a036e7467a53b21532e889601a26cc6dc39d9",
}

M.SHIM = [[#!/bin/sh
# nv4j: snacks.image runs `mmdc -i SRC -o FILE -b transparent -t THEME -s SCALE`; mmdr takes -i -o -t and writes PNG.
d=$(dirname "$0"); i=; o=; t=default
while [ $# -gt 0 ]; do
  case "$1" in -i) i=$2; shift ;; -o) o=$2; shift ;; -t) t=$2; shift ;; -b | -s) shift ;; esac
  shift
done
exec "$d/mmdr" -i "$i" -o "$o" -e png -t "$t"
]]

function M.dir() return vim.fn.stdpath("data") .. "/mermaid" end
function M.installed() return vim.uv.fs_stat(M.dir() .. "/mmdr") ~= nil and vim.uv.fs_stat(M.dir() .. "/mmdc") ~= nil end

--- Target triple of this machine, or nil when no release exists for it.
function M.target()
  local u = vim.uv.os_uname()
  local arch = (u.machine == "arm64" or u.machine == "aarch64") and "aarch64" or (u.machine == "x86_64" and "x86_64" or nil)
  if not arch then return nil end
  if u.sysname == "Darwin" then return arch .. "-apple-darwin" end
  if u.sysname == "Linux" then return arch .. "-unknown-linux-gnu" end
end

local function sha256(file)
  local cmd = vim.fn.executable("sha256sum") == 1 and { "sha256sum", file } or { "shasum", "-a", "256", file }
  local r = vim.system(cmd, { text = true }):wait()
  return r.code == 0 and (r.stdout or ""):match("^(%x+)") or nil
end

local function note(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "Nv4J Mermaid" }) end

--- Put the directory first on PATH (snacks finds `mmdc` there). Cheap: one stat; no-op until installed.
function M.setup()
  if vim.g.nv4j_mermaid == false or not M.installed() then return end
  local d = M.dir()
  vim.schedule(function() M.hook() end)
  if not (vim.env.PATH or ""):find(d, 1, true) then vim.env.PATH = d .. ":" .. (vim.env.PATH or "") end
end

-- Mermaid placements per buffer, recorded by wrapping Snacks.image.placement.new (snacks keeps no registry), so toggle()
-- can flip `conceal` on them. conceal = the code lines are hidden and the image takes their place; the source shows again
-- while the cursor is inside the block (snacks hides the image under the cursor). Default is off: code visible, image below.
local tracked, wrapped = {}, false
local function hook()
  if wrapped or not rawget(_G, "Snacks") or not Snacks.config.image or not Snacks.config.image.enabled then return end
  wrapped = true
  local P = Snacks.image.placement
  local orig = P.new
  P.new = function(buf, src, opts)
    if opts and opts.type == "chart" then opts.conceal = vim.b[buf].nv4j_mermaid_hide == true end
    local p = orig(buf, src, opts)
    if opts and opts.type == "chart" then
      tracked[buf] = tracked[buf] or {}
      tracked[buf][p.id] = p
    end
    return p
  end
end
M.hook = hook

--- <leader>cm: flip this buffer between "code visible, image below" and "image instead of the code" (the text is only hidden).
function M.toggle()
  hook()
  local buf = vim.api.nvim_get_current_buf()
  if not wrapped then return note("mermaid is not enabled: :Nv4JMermaid install, then restart", vim.log.levels.WARN) end
  local hide = not (vim.b[buf].nv4j_mermaid_hide == true)
  vim.b[buf].nv4j_mermaid_hide = hide
  local n = 0
  for id, p in pairs(tracked[buf] or {}) do
    if p.closed then tracked[buf][id] = nil else
      p.opts.conceal = hide
      p._state = nil -- snacks skips a re-render when its window state is unchanged; conceal is not part of that state
      pcall(p.update, p)
      n = n + 1
    end
  end
  note((hide and "image instead of the code" or "code visible") .. " (" .. n .. " diagram" .. (n == 1 and "" or "s") .. ")")
  return n
end

function M.install()
  local target = M.target()
  if not target then return note("no mmdr release for " .. vim.uv.os_uname().sysname .. " " .. vim.uv.os_uname().machine, vim.log.levels.ERROR) end
  for _, t in ipairs({ "curl", "tar" }) do
    if vim.fn.executable(t) ~= 1 then return note(t .. " is required", vim.log.levels.ERROR) end
  end
  local dir = M.dir()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local tgz = tmp .. "/mmdr.tgz"
  note("downloading mmdr " .. M.VERSION .. " (" .. target .. ")")
  vim.system({ "curl", "-fsSL", "-o", tgz, BASE .. target .. ".tar.gz" }, {}, function(r)
    vim.schedule(function()
      local function fail(msg)
        vim.fn.delete(tmp, "rf")
        note(msg, vim.log.levels.ERROR)
      end
      if r.code ~= 0 then return fail("download failed (curl exit " .. r.code .. ")") end
      local got = sha256(tgz)
      if got ~= M.SHA[target] then return fail("SHA-256 mismatch, nothing installed (got " .. tostring(got) .. ")") end
      vim.fn.mkdir(dir, "p")
      local x = vim.system({ "tar", "xzf", tgz, "-C", dir, "./mmdr" }, { text = true }):wait()
      if x.code ~= 0 then return fail("unpack failed: " .. (x.stderr or "")) end
      vim.uv.fs_chmod(dir .. "/mmdr", tonumber("755", 8))
      local f = assert(io.open(dir .. "/mmdc", "w"))
      f:write(M.SHIM)
      f:close()
      vim.uv.fs_chmod(dir .. "/mmdc", tonumber("755", 8))
      vim.fn.delete(tmp, "rf")
      M.setup()
      note("installed in " .. dir .. ". Restart Neovim, then open a markdown file with a ```mermaid block.")
    end)
  end)
end

function M.remove()
  vim.fn.delete(M.dir(), "rf")
  note("removed " .. M.dir() .. " (restart Neovim to drop it from PATH)")
end

function M.status()
  local ver = M.installed() and vim.trim(vim.system({ M.dir() .. "/mmdr", "--version" }, { text = true }):wait().stdout or "") or "not installed"
  local sup = "unknown"
  if rawget(_G, "Snacks") and Snacks.image then sup = tostring(Snacks.image.supports_terminal()) end
  note(("mmdr: %s\nterminal images: %s\ndir: %s\ntarget: %s"):format(ver, sup, M.dir(), tostring(M.target())))
end

return M
