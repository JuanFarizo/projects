-- Spring Boot language server (D14): JavaHello/spring-boot.nvim pinned, configured by nv4j/spring.lua.
-- Server: Mason package vscode-spring-boot-tools. Off with vim.g.nv4j_spring = false.
return {
  {
    "JavaHello/spring-boot.nvim",
    commit = "9880be48170a21d97444b1eba75853fd3bad33c3",
    ft = { "java", "yaml", "jproperties" },
    -- vim.g.nv4j_spring = false (options.lua): not loaded at all (no :SpringBoot, no sts commands, no client).
    cond = function() return vim.g.nv4j_spring ~= false end,
    config = function() require("nv4j.spring").setup() end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      if vim.g.nv4j_spring ~= false then
        opts.ensure_installed = opts.ensure_installed or {}
        table.insert(opts.ensure_installed, "vscode-spring-boot-tools")
      end
    end,
  },
}
