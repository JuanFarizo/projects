-- Spring Boot language server (D14): JavaHello/spring-boot.nvim pinned, configured by nv4j/spring.lua.
-- Server: Mason package vscode-spring-boot-tools. Off with vim.g.nv4j_spring = false.
-- Plugin and Mason install wait for a Boot project (cwd, or the first Boot file opened).
return {
  {
    "JavaHello/spring-boot.nvim",
    commit = "9880be48170a21d97444b1eba75853fd3bad33c3",
    lazy = true,
    -- vim.g.nv4j_spring = false (options.lua): not loaded at all (no :SpringBoot, no sts commands, no client).
    cond = function() return vim.g.nv4j_spring ~= false end,
    init = function() require("nv4j.spring").watch() end,
    config = function() require("nv4j.spring").setup() end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      if require("nv4j.spring").want_install() then
        opts.ensure_installed = opts.ensure_installed or {}
        table.insert(opts.ensure_installed, "vscode-spring-boot-tools")
      end
    end,
  },
}
