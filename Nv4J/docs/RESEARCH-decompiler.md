# Research: library sources and decompiler for go-to-definition

Status: research only (2026-11-10). Nothing was downloaded, installed, loaded into jdt.ls or changed in the product.
Probe files: `/tmp/nv4j/decomp/` (probe.lua, run.sh, proj/, r_unset.txt, r_true2.txt). Claims marked (K) are from knowledge or a web page I could not confirm locally.

## 1. Short answer for the owner

The installed jdt.ls 1.63.0 ALREADY contains a decompiler: IntelliJ's Fernflower (`wrapped.com.jetbrains.intellij.java.java-decompiler-engine_253.29346.240.jar`, 940,441 bytes, in `~/.local/share/nv4j/mason/packages/jdtls/plugins/`). Go to definition into a library class with no sources jar already shows decompiled Java today, with no setting and no download. `docs/RESEARCH-ide-gap.md` row "Navigate into library sources / decompiled" and open question 4 ("no decompiler found") are wrong about the decompiler: that checkout of jdt.ls is a sparse one and does not contain the decompiler classes. The recommendation is therefore: do not add a decompiler; at most add the two `downloadSources` settings.

## 2. What the terms mean

- Library: a `.jar` your project uses (Spring, commons-codec). It holds compiled `.class` files only.
- Sources jar (`name-1.2-sources.jar`): a second jar next to it with the original `.java` files, comments and parameter names included. Maven Central publishes them for most open-source libraries; internal or old artifacts often have none.
- Decompiler: a program that rebuilds Java from `.class` files. The result is readable but is a reconstruction.

Trade-offs:

| | Real sources jar | Decompiled (Fernflower) |
|---|---|---|
| Comments / Javadoc | yes | none |
| Parameter names | original | `var1, var2` unless the jar was compiled with `-parameters`/debug info |
| Line numbers | match the stack traces and the debugger | do not match the original (the header says so); breakpoints in library code are unreliable (K) |
| Correctness | exact | usually right, can be wrong or fail on lambdas, switch patterns, newest bytecode (K) |
| Speed | instant (file read) | measured 150-250 ms for a 222-line class |
| Needs network | once, to fetch the jar | never |
| Licence | the library's own | Fernflower Apache-2.0 (K) |

## 3. Verified on this machine

Setup: `/tmp/nv4j/decomp/proj` (plain Maven, JDK 21 release), depends on commons-logging 1.2 (a `-sources.jar` exists in `~/.m2`) and commons-codec 1.20.0 (no sources jar in `~/.m2`). Real jdt.ls 1.63.0 through the product config in headless Neovim (NVIM_APPNAME=nv4j, Spring LS off), `textDocument/definition` on `LogFactory` and on `Hex`, then `:edit` of the returned `jdt://contents/...` URI (nvim-jdtls blocks until `java/classFileContents` answers; product timeout 20 s). Offline: the probe forced `java.import.maven.offline.enabled=true` so no network access was possible. Fresh jdt.ls workspace per run, one jdt.ls at a time.

| Case | Settings (effective, printed by the probe) | Result: first lines of the buffer |
|---|---|---|
| (a) sources jar present (LogFactory) | downloadSources unset | 1704 lines, starts with the real `/* Licensed to the Apache Software Foundation ...` header and Javadoc. 194 ms |
| (b) no sources jar (Hex) | unset | 222 lines, line 1 `// Source code is decompiled from a .class file using FernFlower decompiler (from Intellij IDEA).`, then `package org.apache.commons.codec.binary;`, imports, `public class Hex implements BinaryEncoder, BinaryDecoder {`, `public static final Charset DEFAULT_CHARSET;`. 156 ms. No comments |
| (c) both, `java.maven.downloadSources=true` and `java.eclipse.downloadSources=true` (fresh workspace) | true | identical to (a) and (b). With the network blocked nothing could be fetched, so this proves only that the setting does not change anything when the sources are already local or unreachable |

Not verifiable without a download (not done): that `downloadSources=true` really fetches a missing `-sources.jar` from the remote repository. I only read the code path: the setting is `java.maven.downloadSources` / `java.eclipse.downloadSources`, real default `false` in the pinned source (`Preferences.java` lines 983-984, reset defaults) and the product sets neither (grep of `nvim/lua` finds no `downloadSources`). The decompiler answer for (b) therefore is today's behaviour for every library without a local sources jar, and after enabling the setting a library with a published sources jar would switch from decompiled to real source after the download and a re-open (K: the real source appears once m2e attaches the jar to the classpath entry).

So: sources do NOT always work. They exist only if the jar was downloaded; with the default settings Maven only pulls sources if something else (IDE, `mvn dependency:sources`) put them in `~/.m2`. What you see when they are missing is the decompiled code, not an error.

What happens if no provider answers (source code, not run): `ContentProviderManager.getContent` returns the empty string `""` and logs "Unable to find content provider for URI"; the buffer would open empty. The bundled Fernflower provider is registered in the installed `plugin.xml` as `fernflowerContentProvider`, `priority="2147483647"`, `uriPattern=".+\.class.*"`; `sourceContentProvider` has priority 0. Providers are sorted ascending (lowest number first, per the upstream `ContentProviderManager` source page) and the first non-null result wins, which matches the measurements: attached sources first, Fernflower as the fallback. A user can force an order with `java.contentProvider.preferred` (key in `Preferences.java:488`).

## 4. Options

| Option | How | Effort | Size | Licence | Risk |
|---|---|---|---|---|---|
| 0. Do nothing (current) | bundled Fernflower 253.29346.240 | none | already installed, 0.9 MB | Apache-2.0 (K) | stack traces/debug line numbers do not match decompiled code; no comments |
| 1. Turn on `java.maven.downloadSources` + `java.eclipse.downloadSources` | two settings in `plugins/java.lua` | S | sources jars per library (typically 0.1-5 MB each, K) | per library | first definition into a new library triggers a network download; slower first open; fails offline or for private repos (the K12 Nexus here, unverified); real comments and parameter names |
| 2. dgileadi/vscode-java-decompiler | extension adds `java.decompiler.[id]` settings and providers for Fernflower, CFR, Procyon (README lists all three as supported; Fernflower default) | M | not stated on the page; I could not confirm the bundle is shipped in the repo, the README says the Java source lives in `dg.jdt.ls.decompiler` | EPL-2.0 (README page); bundled decompilers keep their own | page shows no releases/packages, no Marketplace/Open VSX link: distribution unverified, would need a manual `.vsix`/jar fetch and an `init_options.bundles` entry |
| 3. CFR | OSGi wrapper plus provider | L | cfr-0.152.jar 2,162,315 bytes (Maven Central listing) | MIT (K, page fetch failed) | handles newer Java syntax better than old Fernflower (K); needs writing a provider extension |
| 4. Procyon | same | L | not verified | Apache-2.0 (GitHub page) | repository page shows no release; project seems idle (K) |
| 5. Newer Fernflower | replace the wrapped jar | M | about 1 MB | Apache-2.0 (K) | the installed one is already 253.x (2025.3); no gain |

Mechanism for any decompiler: a plugin contributes to the extension point `org.eclipse.jdt.ls.core.contentProvider` (provider class with `getContent(uri, monitor)`, `priority`, `uriPattern`), loaded as an OSGi bundle through `initializationOptions.bundles` (confirmed in the installed `plugin.xml`; the pinned source tree is sparse and lacks `ContentProviderManager`, so selection logic was read from the upstream page). The client calls `java/classFileContents` (JDTLanguageServer.java:1032) or `java.decompile` for `*.class` files (nvim-jdtls source).

How the repo fetches bundles today: java-debug and java-test come from Mason (`mason-registry`, `pkg:openvsx/vscjava/...`, vsix extracted under `~/.local/share/nv4j/mason/packages/<name>/extension`, links under `mason/share/<name>/*.jar`, see `mason-receipt.json`). `plugins/java.lua` globs `$MASON/share/java-test/*.jar` into `config.init_options.bundles` (lines ~164-176). A decompiler bundle would copy that pattern, but only if a Mason package or an Open VSX id exists for it (unverified).

## 5. Recommendation

Sources only plus the bundled decompiler as fallback; no new decompiler download. Concretely: keep Fernflower (zero effort, already works), and optionally enable the two `downloadSources` settings so libraries that have published sources show real code and comments. The owner should decide whether a network fetch on first navigation is acceptable (corporate Nexus, offline work). Adding CFR/Procyon only makes sense if Fernflower is shown to fail on specific Java 21/25 classes, which no test here showed.

## 6. The test that would prove it later

Fixture: a small Maven project like `/tmp/nv4j/decomp/proj` committed under `tests/fixtures`, whose two dependencies are pre-seeded in a throwaway local repository (one with a sources jar, one without) so the check runs offline and without touching `~/.m2`; `java.import.maven.offline.enabled=true` in the check.
Run: `tests/run.sh` new check `95_library_nav`; open `App.java`, request `textDocument/definition` on `LogFactory` and on `Hex`, `:edit` the `jdt://` URI, with deadline loops and a real sleep (no instant sync requests in `vim.wait`).
Assert: (a) buffer contains `Licensed to the Apache Software Foundation` and more than 1000 lines; (b) first line contains `decompiled from a .class file using FernFlower`, contains `public class Hex`, more than 100 lines, and does not contain `Failed to get sources` or an empty buffer; (c) if option 1 is adopted: effective settings include `downloadSources=true` (assert via `client.config.settings`).
Negative controls: (1) `java.contentProvider.preferred` set to an id that matches nothing together with removing the fernflower provider is not possible without editing; use instead the control "jar entry without a class file name (`jdt://` URI of a missing class)" must give the empty-buffer path and the assert for (b) must fail; (2) a run where the sources jar is hidden from the first project must produce the `FernFlower` header instead of the Apache header, so the (a) assert fails.

## 7. Decision for the owner

1. Accept the bundled decompiler as the answer (recommended, no work), or require real sources always?
2. If real sources: allow network fetch on first navigation (`downloadSources=true`)? Yes gives comments and exact line numbers, no keeps everything offline.
3. Only if Fernflower fails on classes you actually use: authorise a second decompiler (CFR) as a new, separately approved download task.

## Unverified

Fernflower and CFR licences and the typical sizes of sources jars (K); Procyon jar size; that the dgileadi repo ships a bundle and where it is published; real network behaviour of `downloadSources=true`; behaviour when Fernflower fails on a class; whether the K12 Nexus serves sources jars.
