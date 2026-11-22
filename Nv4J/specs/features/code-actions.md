# Feature: jdt.ls code actions, proven

Status: proven by `tests/checks/91_codeactions.lua` (2026-11-10, jdt.ls 1.63.0 from Mason). Closes row 13 of the top-15 list in `docs/RESEARCH-ide-gap.md` for every framework-agnostic action that jdt.ls offers. Checks 31 and 32 already proved organize imports, the quick fixes (create method / variable / class, import, implement methods, remove unused), getters and setters, constructors, `toString()`, `equals` / `hashCode` and extract variable / constant / method on one occurrence; this check covers the rest.

## How the check works

- A plain Maven project `/tmp/nv4j/ca91` (no Spring, so the import takes seconds), recreated on every run. Each case plants a class body in the `Ca.java` buffer (memory only), waits for the diagnostic it needs (if any), asks `textDocument/codeAction` at the cursor or selection (the diagnostics of the range as context, like `<leader>ca`), then applies the action through `vim.lsp.buf.code_action` (resolve, edit or client command, so nvim-jdtls's own handlers for `java.action.*` run). Three extract cases call the functions behind the keys (`require("jdtls").extract_variable_all(true)` and so on) with the selection set as marks.
- Asserted: the exact text of the whole file after the action (imports included), then no ERROR diagnostic (a publish after the edit is awaited, polled with a real 250 ms sleep per round, and the state must hold 1.5 s).
- `*_not_offered` cases pass only when the codeAction list verifiably lacks every listed title (several positions asked for the type-level ones). That is a finding, not a failure.
- Only UI prompts are stubbed: nvim-jdtls's `vim.fn.input` multi-picker (Override, Delegate: the case types the number of the wanted method), `vim.fn.inputlist`, `vim.ui.input` (rename after extract: cancelled), `vim.ui.select` (Move: "new file").
- No product bug found: every action jdt.ls offers produced the right edit through Nv4J's setup, no Nv4J Lua was changed for this task. CORRECTION (2026-11-16): that statement covers the Lua-driven path only. The `*_key` cases call `require("jdtls").extract_constant(true)` from Lua with marks set from Lua, and the key check only asks that the mapping exists; no key was pressed. Pressed keys are now proven by check 100 (below), which found a product gap (silent no-op on a selection that is not a whole expression) and fixed it.

## Pressed keys (check `100_extract_keys`, 2026-11-16)

One real nvim (`NVIM_APPNAME=nv4j`) in a private `tmux -L xc100-<pid>` with one jdt.ls on a tiny Maven project; keys sent with `tmux send-keys`, the BUFFER text read through the nvim socket, the screen through `capture-pane`. Proven by keypress: `<leader>cxc` (normal on `2` of `2 * 3`: a "Choices" picker lists `2` and `2 * 3`, Down + Enter; visual `v4l`; visual `vi"` inside a string; default package), `<leader>ca` menu + filter "to constant" and "lambda" + Enter, `<leader>cxv` (normal with picker, visual), `<leader>cxm` (visual lines), `<leader>ji`, `<leader>co`. Everything else in the table below is proven by the Lua path only.

Findings from pressing the keys:

- Not reproduced: `<leader>cxc` failing on a literal, in a package, in the default package, or on the real codecrafters-redis copy (`split("\\r\\n")`, `new byte[1024]`): all produced the constant.
- With the cursor on a literal inside an expression (`2` of `2 * 3`, `1024` of `new byte[1024]`) nvim-jdtls opens a "Choices" picker (jdt.ls `java/inferSelection` returns the literal and the enclosing expression); nothing changes until Enter. By design, not a bug.
- Product gap, fixed in `nv4j/extract.lua`: when the selection is not a whole expression (`vi"` on a string, `viw`, `V`, the cursor on whitespace) jdt.ls answers `null` and nvim-jdtls says nothing (cursor case: a `print` that vanishes). Now: `vi"` / `vi'` and edge blanks are widened or trimmed to the literal before the request (extract variable and constant), and one WARN notification says "nothing under the cursor" / "the selection is not a whole expression". Keys bound buffer-local from `on_attach` (they win over LazyVim's which-key ones). `V` (linewise) on a statement still extracts nothing: a statement is not an expression, only the WARN is new.
- jdt.ls limitation (evidence: the `java/getRefactorEdit` answer, no Nv4J code between): extract constant on a LONE NUMBER literal (`42`, `7`) replaces only the selected occurrence; strings (`"\\r\\n"`) and `2 * 3` replace every occurrence. Case `cxc_ca_menu` pins it.

Cases: `cxc_normal_pick`, `cxc_visual`, `cxc_visual_quotes`, `cxc_ca_menu`, `cxc_default_package`, `cxc_nothing_cursor`, `cxc_nothing_selection`, `cxv_normal`, `cxv_visual`, `cxm_visual`, `ji_inline`, `co_organize`, `ca_lambda`. Controls (`tests/lib/control_100.sh`): nonorm, nowarn, wrongkind, nobind.

## Code actions proven

Key to trigger: `<leader>ca` (LazyVim, normal or visual mode) lists the actions at the cursor or selection and applies the one picked; "ca" in the last column means exactly that. The extract trio also has its own keys from LazyVim's jdtls extra: `<leader>cxv` extract variable (all occurrences), `<leader>cxc` extract constant, `<leader>cxm` extract method (visual mode). `<leader>co` organize imports (check 31).

| Action | Offered by jdt.ls | Proven by case | Notes / limits | Key |
|--------|-------------------|----------------|----------------|-----|
| Extract to local variable, all occurrences | yes | `extract_variable_all`, `extract_variable_key` | replaces both `2 * 3`; jdt.ls names it `i` (the rename prompt follows, cancelled in the check) | ca, `<leader>cxv` |
| Extract to constant (replaces every occurrence) | yes | `extract_constant_all`, `extract_constant_key` | (Lua path; keys pressed in check 100) `private static final int INT`, both uses replaced. There is no separate "replace all" title: the single action replaces all | ca, `<leader>cxc` |
| Extract to field | yes | `extract_field` | `private int i;` plus assignment in place (field initialised in the method, not at the declaration) | ca |
| Extract to method with parameters | yes | `extract_method_params`, `extract_method_key` | locals read in the selection become parameters (`getZ(int x, int y)`), the result is returned | ca, `<leader>cxm` |
| Introduce parameter | yes ("Introduce Parameter...") | `introduce_parameter` | `42` becomes new parameter `i` | ca |
| Introduce parameter object | NOT OFFERED | `introduce_parameter_object_not_offered` | no such action in jdt.ls 1.63.0 | none |
| Extract lambda body to method | yes | `extract_lambda_body` | offered with the cursor on the parameter of an expression lambda, not on a block lambda's arrow | ca |
| Convert anonymous class to lambda | yes | `anon_to_lambda` | | ca |
| Convert anonymous class to nested class | yes | `anon_to_nested` | `private final class RunnableImplementation` | ca |
| Convert lambda to method reference | yes | `lambda_mref_arrow`, `lambda_mref_func`, `lambda_mref_sel` | `System.out::println`, `String::length`; offered with the cursor on `->` or on the parameter | ca |
| Convert lambda to anonymous class | yes | `lambda_to_anon` | adds `@Override` | ca |
| Lambda body expression to block, block to expression | yes | `lambda_expr_to_block`, `lambda_block_to_expr` | | ca |
| Add inferred lambda parameter types | yes | `lambda_infer_types` | `(String s) -> ...` | ca |
| Convert to enhanced `for` | yes | `for_to_foreach` | variable named `element` | ca |
| Convert for-each to indexed / iterator `for` | NOT OFFERED | `foreach_to_indexed_for_not_offered` | | none |
| Convert switch statement to switch expression | yes | `switch_to_expression` | | ca |
| Add missing switch cases | yes (needs the compile error) | `add_missing_cases`, `add_default_case` | adds `case GREEN -> throw new UnsupportedOperationException(...)` and a `default` that throws; the other action adds only the default | ca |
| String concatenation to StringBuilder / String.format / MessageFormat | yes (all three) | `concat_stringbuilder`, `concat_string_format`, `concat_messageformat` | MessageFormat also adds `import java.text.MessageFormat;` (the check compares the whole file, imports included) | ca |
| Convert string concatenation to text block | yes, titled "Convert String concatenation to Text Block" (re-probed 2026-11-21; the earlier "not offered" came from a `return "a\n" + "b\n";` shape) | `string_to_text_block`, `string_to_text_block_return_not_offered` | offered for a concatenation of string literals with line breaks in a variable declaration, assignment or field (`String s = "line1\n" + "line2\n" + "line3\n";` becomes a `"""` block); NOT offered for a `return` of two pieces. Quick assist, no client capability needed | ca |
| Generate delegate methods | yes ("Generate Delegate Methods...") | `delegate_methods` | multi-select through `vim.ui.select` (checkbox list, "Done" first, Esc finishes; `nv4j/codegen.lua`, check 110); the case answers with the number of the wanted line | ca |
| Override / implement methods | yes ("Override/Implement Methods...") | `override_methods` | same multi-select; nothing is selected by default, so "Done" alone does nothing | ca |
| Sort members | yes ("Sort Members for 'Ca.java'") | `sort_members` | fields first in their order, methods sorted by name | ca |
| Add braces / remove braces | NOT OFFERED | `add_braces_not_offered`, `remove_braces_not_offered` | none for `if` (the cleanup "use blocks" is not a code action) | none |
| Invert condition | yes ("Invert conditions") | `invert_condition` | `a < b` becomes `a >= b` | ca |
| Split / join variable declaration | yes | `split_declaration`, `join_declaration` | | ca |
| Assign statement to new local / new field | yes | `assign_to_local`, `assign_to_field` | `int size = l.size();`, `private int size;` plus assignment | ca |
| Convert local variable to field | yes, titled "Extract to field" | `local_to_field` | there is no action with the title "Convert local variable to field" | ca |
| Inline local variable | yes | `inline_local` | `return (a + 1) * 2;` | ca |
| Surround with try/catch | yes | `surround_try` | empty catch body | ca |
| Add throws declaration | yes (needs the compile error) | `add_throws` | | ca |
| Change type (type mismatch) | yes (needs the compile error) | `change_type` | | ca |
| Convert `var` to explicit type / explicit type to `var` | yes, titled "Change type of 'x' to ..." | `var_to_explicit`, `explicit_to_var` | explicit-to-`var` is offered for `int x = 5` | ca |
| Make local `final` / make everything `final` where possible | yes | `final_local`, `final_where_possible` | the second makes parameters and locals `final` in the whole method | ca |
| Add access modifier | yes | `add_access_modifier` | `private int x;` | ca |
| Make static | yes | `make_static` | | ca |
| Getter and setter for one field | yes | `getter_setter_one_field` | the all-fields generators are check 32 | ca |
| Encapsulate field | NOT OFFERED | `encapsulate_field_not_offered` | the per-field getter/setter above is the nearest; it does not make the field private or rewrite uses | none |
| Add Javadoc comment | yes | `javadoc` | `@param` / `@return` skeleton | ca |
| Add `@SuppressWarnings` | yes | `suppress_warnings` | `@SuppressWarnings("unused")` | ca |
| Extract interface | yes, only when the client says `extractInterfaceSupport` (+ `advancedExtractRefactoringSupport`) in its extended capabilities: "Extract interface..." (kind `refactor.extract.interface`, command `java.action.applyRefactoringCommand` `extractInterface`). nvim-jdtls does not send that flag, so with Nv4J today it is NOT offered (`extract_interface_not_offered` stays true) | `extract_interface_not_offered` | probed on the installed 1.63.0 (check `119_ca_probe`, `NV4J_PROBE_IFACE=1`). NOT built: the flow after the action is client work (`java/checkExtractInterfaceStatus` for members, an interface name, a package node, then `java/getRefactorEdit` with `[handleIdentifiers, name, packageNode]`; the edit creates a new file) and nvim-jdtls has no handler for it | none |
| Move inner type to its own file | yes ("Move 'Inner'...") | `move_inner` | nvim-jdtls asks "new file" or "another class"; "new file" leaves an unsaved `Inner.java` buffer with `class Inner {}` (the `static` is dropped), the file is written when saved | ca |
| Convert class to record | yes, titled "Convert to record" (re-probed 2026-11-21) | `class_to_record`, `class_to_record_not_simple_not_offered` | offered on the class when JDT's own conditions hold: no superclass, private final fields, a constructor, public accessors named `getX`/`x` and a public constructor (the same class with package-private constructor and accessors was NOT offered). Result `public static record P(int a, String b) {\n    }`. Quick assist, no capability needed | ca |
| Record accessors | n/a | | no record action exists; accessors are implicit | none |

## Findings

- Not offered by jdt.ls 1.63.0 (verified absent):  introduce parameter object, indexed / iterator for loop, add / remove braces, extract interface (without the client flag, see its row), encapsulate field, .. They would need Nv4J's own Lua over `textDocument/references` and edits, or a cleanup setting (`java.cleanup.actions` / save actions), not a config key.
- Actions that need a client prompt work through nvim-jdtls (delegate, override, move type, hashCode/equals, constructors, extract's rename). With the real UI the pickers are `vim.fn.input` prompts (type the numbers) and `vim.ui.select`.
- A selection is needed for the extract family with an expression; a cursor works for `Extract to field` on a local variable and for the lambda actions.

## Controls and runs

- Negative controls (env `NV4J_CA_CONTROL`, run with `NV4J_CA_NAMES=<case>`): `noinput` (pickers answer nothing): `delegate_methods` and `override_methods` FAIL (no edit applied); `nokey` (the extract key function is not called): `extract_variable_key` FAILS; `noedit` (workspace edits not applied): `anon_to_lambda` and `sort_members` FAIL; `keeperror` (a type error left in the file): `change_type` FAILS with "text exact but ERROR diagnostics remain".
- Final runs of the check on the finished tree (61 PASS, 0 FAIL each): see the dated line in `docs/TODO.md` for the load at each run.
- Run the check alone: `NV4J_CHECKS='91_*' tests/run.sh` (about 2.5 minutes, it starts its own jdt.ls on `/tmp/nv4j/ca91`). `NV4J_CA_PROBE=1` lists the offered titles and dumps the resulting texts to `/tmp/nv4j/ca91_probe.txt` and `ca91_dump.lua` when adding a case.

## Re-probe of the "not offered" rows on the installed jdt.ls 1.63.0 (2026-11-21, `tests/probes/ca_probe_119.lua`)

Question: which of text block, class to record, extract interface and the extract field scopes does the INSTALLED server offer when asked with the right shape, capability and arguments (the clone `b52e20a` is newer than 1.63.0, so the clone alone proves nothing)? The installed jars contain `getStringConcatToTextBlockProposal`, `ConvertRecordSubProcessor`, `getExtractInterfaceProposal`, `getInitializeScopes` and the `extractInterfaceSupport` client preference.

| Action | Result on 1.63.0 | Done |
|---|---|---|
| Text block | offered (the older case asked the wrong shape: a `return` of two pieces) | case `string_to_text_block` (exact text), `_return_not_offered` |
| Class to record | offered when the constructor and accessors are public (JDT `ConvertToRecordRefactoring` conditions) | case `class_to_record`, `_not_simple_not_offered` |
| Extract interface | offered only with the client capability `extractInterfaceSupport`; the action is a command, the rest is client work (members, name, package) | not built: no client flow exists, nvim-jdtls has no handler; recorded here |
| Extract field `initializeIn` scopes | the action carries `{ initializedScopes = { "Current method" } }` for a local variable and for an expression in a method; the other scopes ("Field declaration", "Class constructors") appear only when JDT says they are possible (none of the probed shapes). nvim-jdtls ignores the third command argument and asks `java/getRefactorEdit` without `commandArguments`, so the default "Current method" is used | not built: the probed shapes offer a single scope, so a chooser would show one entry |

## Multi-select picker (2026-11-21)

nvim-jdtls's `jdtls.ui.pick_many` (override, delegate, toString, hashCode/equals, constructors) was a `vim.fn.input` loop: the user typed numbers. `nv4j/codegen.lua` now replaces it with a loop of `vim.ui.select` (the user's picker): one line per item with `[ ]`/`[x]`, choosing a line toggles it and the list returns, "Done (n selected)" (first line) or Esc finishes. It still blocks and returns the chosen items (nvim-jdtls uses the return value; `vim.wait` until the UI answers, so snacks' asynchronous picker works). `isField` items still start selected. Check `110_pick_many` (10 cases, pure) with controls `tests/lib/control_110.sh` (`noselect`, `oldinput`, `nopre`: each makes its cases FAIL). Check 91 `delegate_methods` and `override_methods` still pass: their stub of `vim.ui.select` replays the same number answers on the checkbox list (`ask.many`); control `NV4J_CA_CONTROL=noinput` still fails both. Unverified: the look and feel in a real snacks picker (no extra terminal was opened).
