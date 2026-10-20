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
            -- ships thousands of items per keystroke and lags typing.
            maxResults = 200,
            filteredTypes = { "com.sun.*", "sun.*", "jdk.internal.*" },
            favoriteStaticMembers = {
              "org.junit.Assert.*",
              "org.junit.jupiter.api.Assertions.*",
              "org.mockito.Mockito.*",
              "org.assertj.core.api.Assertions.*",
              "java.util.Objects.*",
            },
            guessMethodArguments = "insertBestGuessedArguments",
          },
        },
      })

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
      opts.jdtls = vim.tbl_deep_extend("force", opts.jdtls or {}, {
        -- jdtls re-validates (full diagnostics pass) on every didChange with
        -- no debounce of its own — each keystroke restarts the pass, so on a
        -- slow-ish machine it never catches up and fires a diagnostics
        -- publish ~1s after every word. Debounce didChange so it only fires
        -- once typing pauses, instead of on every keystroke.
        flags = {
          debounce_text_changes = 500,
        },
      })
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
