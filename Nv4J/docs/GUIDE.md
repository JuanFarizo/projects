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

Restart Neovim. Now one jdt.ls serves every folder below the `.nv4j`, and classes in sibling folders see each other. Put `.nv4j` in the top folder of the project, not in `$HOME`. If a second jdt.ls starts anyway, Nv4J warns you once and tells you where to put the file.

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
| Rename a class | `<leader>jr` | File, references and imports change. Strings such as JPQL or `application.yml` that still name the old class are listed in a warning, not rewritten |
| Rename a package | `<leader>jp` | Or `<leader>jr` on the `package` line. Folders in `src/main/java` and `src/test/java` move |
| Move a class | `<leader>jm` | Pick a package from the list or type a new one |
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

## 9. Switch the Java version

```sh
sdk use java 21.0.7-amzn
nv4j path/to/File.java
```

jdt.ls runs on the JDK of `$JAVA_HOME` when it starts. The JDK your project compiles with follows the build file (`<maven.compiler.release>` or `.sdkmanrc`).

## 10. Something is slow or wrong

- Completion feels slow: `:CompletionProfile on`, work for a while, `:CompletionProfile off`.
- A refactor looks stuck: wait for the 3 s and 8 s notices; an error is reported when jdt.ls answers late.
- Logs are in `/tmp/nv4j/logs` (jdt.ls: `lsp.log`).
- Memory: one jdt.ls is about 1.3 GB. More than one means a folder without `.nv4j` (recipe 2).
- More: README "Troubleshooting" and "Known limitations".
