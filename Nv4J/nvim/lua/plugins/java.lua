-- Custom overrides on top of LazyVim's `lang.java` extra.
return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- Default root_dir falls back to the nearest `.git`, which for a loose
      -- .java file can mean a whole unrelated repo — breaks jdtls's
      -- invisible-project support. Fall back to the file's own dir instead.
      local build_markers = {
        "pom.xml",
        "build.gradle",
        "build.gradle.kts",
        "settings.gradle",
        "settings.gradle.kts",
        "mvnw",
        "gradlew",
        "build.xml",
      }
      -- Multi-module Maven: prefer the repo's .git root over a submodule's
      -- own pom.xml, but only when that repo actually has a build marker —
      -- otherwise a loose file in an unrelated git repo (e.g. a notes repo)
      -- would wrongly get that whole repo as its root again.
      opts.root_dir = function(path)
        local marker_root = vim.fs.root(path, build_markers)
        if not marker_root then
          return vim.fs.dirname(path)
        end
        local git_root = vim.fs.root(path, { ".git" })
        if git_root then
          for _, marker in ipairs(build_markers) do
            if vim.uv.fs_stat(git_root .. "/" .. marker) then
              return git_root
            end
          end
        end
        return marker_root
      end

      -- JVM that runs jdtls itself (>= 21): $JAVA_HOME if >= 21, else the newest JDK found by
      -- nv4j.jdk (SDKMAN, ~/Library/Java/JavaVirtualMachines, /Library/...). Nothing here reads PATH
      -- or calls the lazy `java` shell function. Raises a clear error if no JDK >= 21 exists.
      -- The per-project runtimes (java.configuration.runtimes) are set in opts.jdtls below, once the
      -- project root is known.
      local server_home = require("nv4j.jdk").server_home()
      table.insert(opts.cmd, "--java-executable=" .. server_home .. "/bin/java")

      -- "0 references" above a method/class = unused, IntelliJ-style. Also
      -- needs opts.codelens.enabled = true on nvim-lspconfig (see lsp.lua) —
      -- jdtls is started directly by nvim-jdtls, not via lspconfig's
      -- servers.jdtls (the extra's setup.jdtls returns true to skip that), so
      -- this setting has to live in nvim-jdtls's own opts.settings.
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          referencesCodeLens = { enabled = true },
          -- Trims low-value jdtls completion candidates (internal JDK
          -- types, unimported static members) blink.cmp can't filter itself.
          completion = {
            -- jdt.ls default (50) hides members on big classes; 0 = unlimited
            -- ships thousands of items per keystroke and lags typing. 1000 was measured
            -- (specs/002-p1-completion.md): `@` becomes a complete list, but identifier lists
            -- stay incomplete and their per-keystroke round trip gets slower, so 200 stays.
            maxResults = 200,
            -- Hidden from completion, auto-import and quick fix (explicit imports still work).
            -- Defaults and the vim.g.nv4j_filtered_types override: nv4j/completion.lua.
            filteredTypes = require("nv4j.completion").filtered_types(),
            favoriteStaticMembers = {
              "org.junit.Assert.*",
              "org.junit.jupiter.api.Assertions.*",
              "org.mockito.Mockito.*",
              "org.assertj.core.api.Assertions.*",
              "java.util.Objects.*",
            },
            guessMethodArguments = "insertBestGuessedArguments",
            -- Import groups, IntelliJ-like (its default: all other, javax, java, static), with
            -- jakarta next to javax. "" = every package no other entry matches, "#" = static imports.
            -- Used by auto-import on completion, quick fix imports and organize imports.
            importOrder = { "", "javax", "jakarta", "java", "#" },
          },
          -- No wildcard imports (jdt.ls default 99; IntelliJ folds at 5/3, Spring's style forbids *).
          sources = { organizeImports = { starThreshold = 99, staticStarThreshold = 99 } },
          -- Organize imports on save stays off, like IntelliJ's default: it would drop an import added
          -- just before its first use. <leader>co organizes on demand.
          saveActions = { organizeImports = false },
          -- Apply pom.xml / build.gradle changes without asking (default "interactive" leaves a
          -- "may need reload" diagnostic on the build file and a stale classpath).
          configuration = { updateBuildConfiguration = "automatic" },
          -- Generated code close to IntelliJ's defaults: braces, java.util.Objects in
          -- equals/hashCode, ClassName{field=value, ...} toString, no comments.
          codeGeneration = {
            useBlocks = true,
            generateComments = false,
            hashCodeEquals = { useJava7Objects = true, useInstanceof = false },
            toString = {
              template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
              codeStyle = "STRING_CONCATENATION",
            },
          },
        },
      })
      -- Visible notification when jdt.ls reports errors on pom.xml / build.gradle (nv4j/buildfile.lua).
      require("nv4j.buildfile").setup()
      -- Unused-import warnings also while the file has compile errors (JDT drops them; nv4j/unused_imports.lua).
      require("nv4j.unused_imports").setup()

      -- -configuration (jdtls's writable copy of the config) also lives under /tmp/nv4j.
      opts.jdtls_config_dir = function(project_name)
        return require("nv4j.paths").jdtls_config .. "/" .. project_name
      end

      -- LazyVim's project_name = basename(root_dir) collides across every
      -- lambda here (lambdas/<name>/app/pom.xml -> root_dir ends in "app"
      -- for all of them), so they all share one jdtls workspace/config
      -- cache dir and stomp each other's index/classpath. Disambiguate by
      -- hashing the full root_dir path instead of just its basename.
      opts.project_name = function(root_dir)
        return root_dir and (vim.fs.basename(root_dir) .. "-" .. vim.fn.sha256(root_dir):sub(1, 8))
      end

      -- JDTLS workspace (-data) lives under /tmp/nv4j/jdtls-data/<project_name>
      -- instead of stdpath("cache"), see lua/nv4j/paths.lua.
      opts.jdtls_workspace_dir = function(project_name)
        return require("nv4j.paths").jdtls_data .. "/" .. project_name
      end

      -- LazyVim's java extra only forwards a fixed set of opts fields (cmd,
      -- root_dir, init_options, settings, capabilities) plus whatever sits
      -- under opts.jdtls (see its attach_jdtls: `extend_or_override(config,
      -- opts.jdtls)`) into the config it hands to jdtls.start_or_attach —
      -- top-level opts.flags/opts.handlers here are silently ignored, so
      -- anything jdtls.start_or_attach itself needs to see has to go here.
      local static_jdtls = {
        cmd_env = { JAVA_HOME = server_home },
        -- Batch didChange while typing. jdt.ls also debounces on its side (validation <= 400 ms,
        -- publish 400-2000 ms adaptive, BaseDocumentLifeCycleHandler), and Neovim's semantic-token
        -- request flushes pending changes after 200 ms anyway: edit-to-diagnostics measured 460-690 ms
        -- with 500 and the same with 200 (specs/features/diagnostics-imports-actions.md), so 500 stays.
        flags = { debounce_text_changes = 500 },
        -- On ServiceReady, one throw-away completion takes jdt.ls's one-time index cost off the
        -- user's first completion (nv4j/warmup.lua). nvim-jdtls wraps this handler.
        handlers = {
          ["language/status"] = function(err, result) require("nv4j.warmup").status_handler(err, result) end,
        },
      }
      -- LazyVim calls this with the config it built (root_dir known) and uses the return value.
      opts.jdtls = function(config)
        config = vim.tbl_deep_extend("force", config, static_jdtls)
        local runtimes = require("nv4j.jdk").runtimes(config.root_dir)
        config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
          java = { configuration = { runtimes = runtimes } },
        })
        return config
      end
      -- Project usage counts for completion ranking (nv4j/usage.lua), started here at attach
      -- (the only place) so the first completion already has them. LazyVim's java extra calls opts.on_attach from LspAttach.
      local prev_on_attach = opts.on_attach
      opts.on_attach = function(args)
        if prev_on_attach then prev_on_attach(args) end
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client then require("nv4j.usage").watch(client.config.root_dir) end
        -- toString and equals/hashCode field pickers start with all fields selected (nv4j/codegen.lua).
        require("nv4j.codegen").setup()
      end
      -- The "Publish Diagnostics" / "Building" / "Validate documents" toasts
      -- (bottom-right, checkmark list) are jdtls's $/progress notifications,
      -- rendered by noice.nvim's lsp_progress view (LazyVim core ships
      -- noice.nvim by default) — not window/showMessage. Filtered in
      -- plugins/noice.lua instead, at the notification-routing layer, since
      -- that's the layer that actually renders them.

      require("jdtls").settings.jdt_uri_timeout_ms = 20000

      return opts
    end,
  },
}
