# Feature: jdt.ls code actions, proven

Status: proven by `tests/checks/91_codeactions.lua` (2026-11-10, jdt.ls 1.63.0 from Mason). Closes row 13 of the top-15 list in `docs/RESEARCH-ide-gap.md` for every framework-agnostic action that jdt.ls offers. Checks 31 and 32 already proved organize imports, the quick fixes (create method / variable / class, import, implement methods, remove unused), getters and setters, constructors, `toString()`, `equals` / `hashCode` and extract variable / constant / method on one occurrence; this check covers the rest.

## How the check works

- A plain Maven project `/tmp/nv4j/ca91` (no Spring, so the import takes seconds), recreated on every run. Each case plants a class body in the `Ca.java` buffer (memory only), waits for the diagnostic it needs (if any), asks `textDocument/codeAction` at the cursor or selection (the diagnostics of the range as context, like `<leader>ca`), then applies the action through `vim.lsp.buf.code_action` (resolve, edit or client command, so nvim-jdtls's own handlers for `java.action.*` run). Three extract cases call the functions behind the keys (`require("jdtls").extract_variable_all(true)` and so on) with the selection set as marks.
- Asserted: the exact text of the whole file after the action (imports included), then no ERROR diagnostic (a publish after the edit is awaited, polled with a real 250 ms sleep per round, and the state must hold 1.5 s).
- `*_not_offered` cases pass only when the codeAction list verifiably lacks every listed title (several positions asked for the type-level ones). That is a finding, not a failure.
- Only UI prompts are stubbed: nvim-jdtls's `vim.fn.input` multi-picker (Override, Delegate: the case types the number of the wanted method), `vim.fn.inputlist`, `vim.ui.input` (rename after extract: cancelled), `vim.ui.select` (Move: "new file").
- No product bug found: every action jdt.ls offers produced the right edit through Nv4J's setup, no Nv4J Lua was changed for this task.

## Code actions proven

Key to trigger: `<leader>ca` (LazyVim, normal or visual mode) lists the actions at the cursor or selection and applies the one picked; "ca" in the last column means exactly that. The extract trio also has its own keys from LazyVim's jdtls extra: `<leader>cxv` extract variable (all occurrences), `<leader>cxc` extract constant, `<leader>cxm` extract method (visual mode). `<leader>co` organize imports (check 31).

| Action | Offered by jdt.ls | Proven by case | Notes / limits | Key |
|--------|-------------------|----------------|----------------|-----|
| Extract to local variable, all occurrences | yes | `extract_variable_all`, `extract_variable_key` | replaces both `2 * 3`; jdt.ls names it `i` (the rename prompt follows, cancelled in the check) | ca, `<leader>cxv` |
| Extract to constant (replaces every occurrence) | yes | `extract_constant_all`, `extract_constant_key` | `private static final int INT`, both uses replaced. There is no separate "replace all" title: the single action replaces all | ca, `<leader>cxc` |
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
| Convert string concatenation to text block | NOT OFFERED | `convert_to_text_block_not_offered` | the cleanup exists in jdt.ls (`java.cleanup.actions`) but is not a code action; not configured in Nv4J (RESEARCH row "Convert to / from text block") | none |
| Generate delegate methods | yes ("Generate Delegate Methods...") | `delegate_methods` | multi-picker: the user types the number of each method, Enter ends | ca |
| Override / implement methods | yes ("Override/Implement Methods...") | `override_methods` | same multi-picker; nothing is selected by default, so Enter alone does nothing | ca |
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
| Extract interface | NOT OFFERED | `extract_interface_not_offered` | asked at the type name, at `class` and over the whole type | none |
| Move inner type to its own file | yes ("Move 'Inner'...") | `move_inner` | nvim-jdtls asks "new file" or "another class"; "new file" leaves an unsaved `Inner.java` buffer with `class Inner {}` (the `static` is dropped), the file is written when saved | ca |
| Convert class to record | NOT OFFERED | `class_to_record_not_offered` | only Move, getters, constructors and the generators are offered on a class with final fields | none |
| Record accessors | n/a | | no record action exists; accessors are implicit | none |

## Findings

- Not offered by jdt.ls 1.63.0 (verified absent):  introduce parameter object, indexed / iterator for loop, text block, add / remove braces, extract interface, encapsulate field, convert class to record.. They would need Nv4J's own Lua over `textDocument/references` and edits, or a cleanup setting (`java.cleanup.actions` / save actions), not a config key.
- Actions that need a client prompt work through nvim-jdtls (delegate, override, move type, hashCode/equals, constructors, extract's rename). With the real UI the pickers are `vim.fn.input` prompts (type the numbers) and `vim.ui.select`.
- A selection is needed for the extract family with an expression; a cursor works for `Extract to field` on a local variable and for the lambda actions.

## Controls and runs

- Negative controls (env `NV4J_CA_CONTROL`, run with `NV4J_CA_NAMES=<case>`): `noinput` (pickers answer nothing): `delegate_methods` and `override_methods` FAIL (no edit applied); `nokey` (the extract key function is not called): `extract_variable_key` FAILS; `noedit` (workspace edits not applied): `anon_to_lambda` and `sort_members` FAIL; `keeperror` (a type error left in the file): `change_type` FAILS with "text exact but ERROR diagnostics remain".
- Final runs of the check on the finished tree (61 PASS, 0 FAIL each): see the dated line in `docs/TODO.md` for the load at each run.
- Run the check alone: `NV4J_CHECKS='91_*' tests/run.sh` (about 2.5 minutes, it starts its own jdt.ls on `/tmp/nv4j/ca91`). `NV4J_CA_PROBE=1` lists the offered titles and dumps the resulting texts to `/tmp/nv4j/ca91_probe.txt` and `ca91_dump.lua` when adding a case.
