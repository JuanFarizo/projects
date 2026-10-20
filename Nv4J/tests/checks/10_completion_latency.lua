-- P1 completion latency. Run via tests/run.sh. Budgets: specs/002-p1-completion.md.
-- Each case types its trigger into the buffer (in memory only), then measures
-- textDocument/completion round trips: 1 first request (cold for that case; the very first of the
-- process is `cold_first`, budget 400 ms), WARMUP discarded, N timed samples (warm, budget p95).
-- Before every sample the case line is re-set, so jdtls gets a didChange and must reconcile,
-- like a keystroke. Samples go to /tmp/nv4j/logs/latency.jsonl.
vim.o.confirm = false
local lsp = require("lsp")
local C = require("completion")

local BUDGET_P95_MS = 150
local BUDGET_COLD_MS = 400
local WARMUP, N = 3, 90
local src = vim.env.NV4J_FIXTURE .. "/src/main/java/demo/"

-- after: insert the case line after the first line matching this pattern.
-- back: cursor this many bytes before the end of the line (autopaired `)` or `;`).
-- expect: label whose rank is reported (informational; ranking budgets live in 11_*).
local after_main = "Repo repo = new Repo"
local cases = {
  -- Spring-scale cases (Boot 3.5: web, data-jpa, security, validation on the classpath).
  { name = "spring_annotation_list", file = "CustomerController.java", after = "^@RequestMapping", line = "@", expect = "RestController" },
  { name = "table_attrs", file = "Customer.java", replace = "^@Table%(", line = "@Table()", back = 1, expect = "name" },
  { name = "column_attrs", file = "Customer.java", replace = '@Column%(name = "email"', line = "    @Column()", back = 1, expect = "nullable" },
  { name = "http_dsl", file = "SecurityConfig.java", after = "public SecurityFilterChain filterChain", line = "        http.", expect = "authorizeHttpRequests" },
  { name = "jpa_repo_members", file = "CustomerController.java", after = "public Customer create", line = "        repository.", expect = "save" },
  { name = "anno_prefix_auto", file = "CustomerController.java", after = "private final CustomerRepository repository;", line = "    @Auto", expect = "Autowired" },
  { name = "anno_prefix_rest", file = "CustomerController.java", after = "^@RequestMapping", line = "@Rest", expect = "RestController" },
  { name = "spring_identifier_a", file = "CustomerController.java", after = "public ResponseEntity<Customer> update", line = "        a", expect = "amended" },
  { name = "spring_identifier_s", file = "CustomerController.java", after = "public List<Customer> search", line = "        s", expect = "search" },
  -- Toy-scale cases (JDK only).
  { name = "system_members", file = "App.java", after = after_main, line = "        System.", expect = "out" },
  { name = "java_util_pkg", file = "App.java", after = after_main, line = "        java.util.", expect = "List" },
  { name = "new_person_ctor", file = "App.java", after = after_main, line = "        Person p = new Person();", back = 2, expect = "Person" },
  { name = "annotation_list", file = "Person.java", after = "^    }", line = "    @", expect = "MyAnno" },
  -- Plain identifier typing (the most common case): hits java.completion.maxResults.
  { name = "identifier_prefix", file = "Person.java", after = "public String getName", line = "        a", expect = "age" },
}

local fuzzy = C.blink()
lsp.report("10_completion_latency.blink_loaded", fuzzy ~= nil and fuzzy.implementation_type == "rust",
  fuzzy and fuzzy.implementation_type or "blink.cmp not loaded")

local cold_done = false
local import_reported = false
for _, cs in ipairs(cases) do
  local tag = "10_completion_latency." .. cs.name
  local t_open = vim.uv.hrtime()
  local first_open = not import_reported
  local buf = C.open_ready(lsp, src .. cs.file, 120000)
  if first_open then
    import_reported = true
    local import_ms = (vim.uv.hrtime() - t_open) / 1e6
    C.append_latency("jdtls_import", import_ms, 0)
    lsp.report("10_completion_latency.jdtls_import", buf ~= nil, ("%.0f ms from open to ready (info, timeout 120 s)"):format(import_ms))
  end
  if not buf then
    lsp.report(tag, false, "jdtls not ready within 120 s")
  else
    C.scratch(buf, function()
      local lnum, col
      if cs.replace then
        lnum, col = C.put_line(buf, C.find_line(buf, cs.replace), cs.line)
      else
        lnum, col = C.put_line(buf, C.find_line(buf, cs.after) + 1, cs.line, true)
      end
      col = col - (cs.back or 0)

      local first = lsp.complete(buf, lnum, col)
      C.append_latency(cs.name .. ".first", first.ms, #first.items)
      if not cold_done then
        cold_done = true
        C.append_latency("cold_first", first.ms, #first.items)
        lsp.report("10_completion_latency.cold_first", not first.err and first.ms <= BUDGET_COLD_MS,
          ("%.0f ms (budget %d) case=%s count=%d%s"):format(first.ms, BUDGET_COLD_MS, cs.name, #first.items,
            first.err and (" err=" .. first.err) or ""))
      end

      local errs, ms, blink_ms, counts = {}, {}, {}, {}
      local last
      for i = 1, WARMUP + N do
        C.put_line(buf, lnum, cs.line) -- didChange before each request, like a keystroke
        local r = lsp.complete(buf, lnum, col)
        if r.err then errs[#errs + 1] = r.err end
        if i > WARMUP and not r.err then
          ms[#ms + 1] = r.ms
          counts[#counts + 1] = #r.items
          C.append_latency(cs.name, r.ms, #r.items)
          if fuzzy then
            local t0 = vim.uv.hrtime()
            last = C.blink_order(fuzzy, buf, lnum, col, r.items)
            local bms = (vim.uv.hrtime() - t0) / 1e6
            blink_ms[#blink_ms + 1] = bms
            C.append_latency(cs.name .. ".blink_sort", bms, #last)
          else
            last = C.lsp_order(r.items)
          end
        end
      end

      local raw = C.raw(buf, lnum, col)
      local rank = last and C.rank(last, function(it) return it.label == cs.expect end)
      local p50, p95, max = C.pct(ms, 50), C.pct(ms, 95), C.pct(ms, 100)
      local detail = ("first=%.0f p50=%.0f p95=%.0f max=%.0f ms (n=%d, budget p95<=%d) count=%d-%d incomplete=%s"
        .. " blink_sort_p95=%.1f ms rank(%s)=%s top=[%s]%s"):format(
        first.ms, p50, p95, max, #ms, BUDGET_P95_MS, C.pct(counts, 0), C.pct(counts, 100),
        tostring(raw and raw.isIncomplete), C.pct(blink_ms, 95), cs.expect, tostring(rank),
        last and C.labels(last, 5) or "",
        (first.err and (" first_err=" .. first.err) or "")
          .. (#errs > 0 and (" errors=" .. #errs .. " sample_err=" .. errs[1]) or ""))
      lsp.report(tag, not first.err and #errs == 0 and #ms == N and p95 <= BUDGET_P95_MS, detail)
    end)
  end
end

lsp.finish()
