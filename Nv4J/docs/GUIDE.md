# Nv4J guide

Short recipes for the things you do every day. Each one says what to press and what you should see. All keys in one table: [KEYS.md](KEYS.md). Install, measurements and limits: [README.md](../README.md). `<leader>` is Space. Start Nv4J with `nv4j` (an alias for `NVIM_APPNAME=nv4j nvim`).

## 1. Open a project

1. `cd` into the Maven project and run `nv4j src/main/java/com/example/App.java`.
2. jdt.ls starts. Progress shows in the corner. Wait until the toasts stop; completion, diagnostics and refactors need it.
3. Opening only a folder (`nv4j .`) reloads the last session for that folder.

## 2. A folder of plain `.java` files (no `pom.xml`)

Without a marker, each folder gets its own jdt.ls (about 1.3 GB each). Mark the project once:

```sh
touch ~/code/my-practice-folder/.nv4j
```

Restart Neovim. Now one jdt.ls serves every folder below the `.nv4j`, and classes in sibling folders see each other. Put `.nv4j` in the top folder of the project, not in `$HOME`. Without it, only the first loose folder gets a jdt.ls; a file in a second loose folder opens without LSP until you add `.nv4j`, and Nv4J warns you once and tells you where to put the file (`vim.g.nv4j_loose_max` raises the limit).

## 3. Write code and accept completion

1. Type. The menu opens by itself.
2. `<CR>` or `<C-y>` accepts the item. The import is added for you (a late import can take up to a second).
3. `<Tab>` / `<S-Tab>` move between snippet fields.
4. Red or faded code: `<leader>ca` for the fix, `<leader>co` to organize imports.

## 4. Create a class, a Spring controller or a package

1. Press `<leader>jn`. Pick the kind (class, interface, record, enum, annotation, controller, service, repository, entity, package, test).
2. Type the name. `Foo` creates `Foo.java` next to the file you are in (or the folder under the cursor in the file tree).
3. `billing.Invoice` creates the package `billing` and the class in it.
4. The file is written to disk with the right `package` line and then opened.
5. For a test of the current class press `<leader>jt`. It opens the existing test or creates it in `src/test/java`.

## 5. Run tests

| You want | Press |
|----------|-------|
| The test under the cursor | `<leader>tr` |
| The whole class | `<leader>tt` |
| Every test of the project | `<leader>tp` |
| Only what failed last time | `<leader>tf` |
| The last run again | `<leader>tl` |
| Debug the test under the cursor | `<leader>td` (set breakpoints first with `<leader>db`) |

You see `✓` / `✗` / `○` next to each test, an error on the failing assertion line, a summary notification, and the details in the quickfix list (`<leader>to`). Each failure lists the stack frames of your own code; press Enter on one to jump to the line.

## 6. Run and debug a Spring Boot app

1. `<leader>rs` runs the app in a split at the bottom. `<C-c>` (normal mode) stops it; `q` stops it and closes the split.
2. `<leader>rp` asks for a profile first.
3. `<leader>rd` debugs it. `<leader>db` sets breakpoints, `<leader>dc` continues, `<leader>dO` / `<leader>di` / `<leader>do` step.
4. `<leader>rx` stops every run.
5. `<leader>sp` lists the beans and the request mappings; Enter jumps to the code.

## 7. Refactor

Put the cursor on the thing and press the key. Every refactor is one undo (`u`) per file it touched, and a notification lists the files.

| Task | Press | Notes |
|------|-------|-------|
| Rename a class | `<leader>jr` | File, references and imports change; its test classes (`InvoiceTest`, `InvoiceTests`, `InvoiceIT`), the variables declared with the class (`Invoice invoice` becomes `Bill bill`) and subclasses named like it (`InvoiceImpl`) are renamed along, like IntelliJ's defaults. Strings such as JPQL or `application.yml` that still name the old class are listed in a warning, not rewritten |
| Rename a package | `<leader>jp` | Or `<leader>jr` on the `package` line. Folders in `src/main/java` and `src/test/java` move. Into the name of an existing package it merges them (refused, naming the classes, if a class name is in both) |
| Move a class | `<leader>jm` | Pick a package of `src/main/java` or `src/test/java` or type a new one. With the cursor on another class's name, that class moves. If the moved class uses package-private code of its old package (or the reverse) you are shown the list and asked before anything moves |
| Undo a rename or move | `<leader>ju` | Puts files, folders, package lines and imports back (IntelliJ's one undo). `u` in a buffer gives back its text only |
| Inline | `<leader>ji` | On a call: that call. On the declaration: every use, then the declaration goes |
| Change a method signature | `<leader>js` | Type the new signature as one line: `public int total(Invoice invoice, int discount = 0)`. Call sites get the default. A method with implementations can take up to 5 s |
| Safe delete | `<leader>jd` | With usages: nothing is deleted, usages go to the quickfix list. Without: the declaration is removed. A deleted file can come back with `:Nv4jRestoreDeleted` |
| Rename any symbol | `<leader>cr` or `<F2>` | The plain LSP rename (variables, methods, fields) |

Only one refactor runs at a time. If you press a second one you get "a refactor is in progress". You can also use the file tree: `r` on a `.java` file or a package folder does the same rename with the code updated.

Extract uses jdt.ls: `<leader>cxv` variable, `<leader>cxc` constant, `<leader>cxm` method (select the code first for method).

## 8. Find your way around

- Definition `gd`, references `gr`, implementation `gI`, hover `K`.
- Hierarchy `<leader>cS` / `<leader>cP`, calls `<leader>ci` / `<leader>cO`.
- Files `<C-p>`, grep `<C-o>`, methods in this file `<C-m>`, file tree `<C-b>`.
- Terminal `<C-/>`, comment a line `<D-/>` on a Mac, `<A-/>` on Linux (or `gcc` anywhere), AI agents `<leader>a` (Claude `<leader>ac`, Cursor `<leader>ak`).
- Next problem `]d` or `<F8>`, all problems `<leader>xx`.

## 8b. A Gradle project

1. `cd` into the project (the folder with `settings.gradle` or `build.gradle`) and open a Java file: `nv4j app/src/main/java/com/example/App.java`. The first import takes about 20 s; the Gradle wrapper (`gradlew`) is used, Neovim does not see SDKMAN's `gradle` function.
2. A multi-project build is one project: files of `app` and `lib` share one jdt.ls, and `<leader>tp` runs the tests of every sub-project.
3. Run as for Maven: `<leader>rs` (fast, `java -cp`), `<leader>rS` (`./gradlew bootRun`), `<leader>rd` (debug). The Java version comes from `.sdkmanrc`, the pom, or the Gradle build (toolchain, `sourceCompatibility`, also through `libs.versions.toml`, `gradle.properties` or a `buildSrc`/`build-logic` convention plugin).
4. A red "Build file" notification means Gradle could not read the build file; it names the file and the line. Fix it and save it in Neovim (`:w`): the project is imported again.
5. Spring features missing although it is a Boot app? Boot applied only by a plugin from a jar or a repository cannot be seen in the files: create `.nv4j` next to the root `build.gradle` containing `{ "spring_boot": true }` (or `{ "spring_boot": "app" }` for the module folder `app`) and restart Neovim. Boot applied by a `buildSrc`/`build-logic` plugin (script or class) or by the root's `subprojects {}` block is recognised without it.

## 9. Switch the Java version

```sh
sdk use java 21.0.7-amzn
nv4j path/to/File.java
```

jdt.ls runs on the JDK of `$JAVA_HOME` when it starts. The JDK your project compiles with follows the build file (`<maven.compiler.release>` or `.sdkmanrc`).

## 10. Something is slow or wrong

- Completion feels slow: `:CompletionProfile on`, work for a while, `:CompletionProfile off`.
- A refactor looks stuck: wait for the 3 s and 8 s notices; an error is reported when jdt.ls answers late.
- Logs are in `/tmp/nv4j/logs` (Neovim LSP log: `lsp-<project>-<pid>.log`, one per Neovim session, so `:LspLog` shows only this project).
- Memory: one jdt.ls is about 1.3 GB. More than one means a project with its own build file or `.nv4j` plus a loose folder; a second loose folder opens without LSP until it gets a `.nv4j` (recipe 2).
- More: README "Troubleshooting" and "Known limitations".
