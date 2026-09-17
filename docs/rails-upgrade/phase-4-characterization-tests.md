# Phase 4 — Characterization Tests

> ## Goal
> **Write tests that pin the behaviour Rails 5 changes *silently* — the places where the code keeps running and quietly does something different.**
>
> Characterization tests assert what the code does *today*, not what it should do. Their job is to scream when a Rails upgrade changes semantics without raising an error.

**Blocking:** 🔴 Yes for 4.0 (it owns the red `next-rails` job) and for the four 5.0-specific items (4.1–4.4). The rest are strongly recommended but can trail the bump.
**Rails version at the end of this phase:** 4.2.11.3, with a materially better regression net.

---

## Why this phase exists

**Because loud breakage is self-reporting and silent breakage is not.**

`before_filter` was removed in 5.1. There are 37 call sites. On 5.1 the app won't boot — `NoMethodError` at class-definition time. That needs zero tests; it needs the rename [Phase 3](phase-3-backwards-compatible-fixes.md) already did. Writing a test to catch it would be writing a test to tell you something the boot sequence already screams.

What needs tests is code that keeps running: a monkeypatch whose target method vanished, so the patch defines a method nobody calls. A validation that now fires where it didn't. An attribute read that silently returns `nil`.

This phase is scoped to those. It deliberately does **not** try to raise coverage — the 72.64% aggregate is adequate; its *distribution* isn't. Models, the layer Rails changes least, sit at 92%. Controllers, where the breakage lives, sit at 58%.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §2](../../RAILS_UPGRADE_TEST_PRIORITY.md) — "The prioritization principle: silence, not likelihood." The reasoning behind this phase.
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §3](../../RAILS_UPGRADE_TEST_PRIORITY.md) — **B1 through B10 in full.** Each has a "Test to write" paragraph; this phase is those paragraphs, sequenced.
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.3](../../RAILS_UPGRADE_TEST_PRIORITY.md) — **required reading for 4.1.** Why the `belongs_to` test must force the flag on or it asserts nothing.
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §7](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the coverage-adequacy table, per testing-checklist category
- [`TEST_COVERAGE_PLAN.md` §1](../../TEST_COVERAGE_PLAN.md) — per-file coverage, for judging where a test adds signal versus where CI already covers it
- Skill: `references/testing-checklist.md` "Common Test Fixes", `version-guides/upgrade-4.2-to-5.0.md` §3 and §8

## Work items

Ordered by confidence-per-hour, except **4.0, which comes first because it is the one item with a red CI job attached to it.** **4.1–4.4 are the 5.0-blocking set.**

### 4.0 — The ten Rails 5 failures inherited from Phase 3 ✅ *(added after Phase 3; completed in stage B)*

**This item owns exit criterion 13 — turning the gating `next-rails` CI job green.** It arrived
here as [Phase 3's criterion 16](phase-3-backwards-compatible-fixes.md), which Phase 3 could not
close: it cleared every defect that was in its own scope and the job stayed red. What remains is
not mechanical, which is exactly why it belongs in the phase whose method is characterization.
Full diagnosis in [`phase-3-report.md` §6](phase-3-report.md#L402); the current failure list is
also in the [`next-rails` job comment](../../.github/workflows/ci.yml).

> ✅ **Closed.** Both bundles are fully green — 5.0 at 780 unit / 145 spec / 89 functional /
> 7 orphan / 154 cucumber, 0F/0E — and the `next-rails` job is green for the first time since
> Phase 2 made it gating. **This also unblocks [Phase 0](phase-0-baseline-and-ci.md)'s criteria
> 1–2**, which needed a green run on the default branch.
>
> Three of the four root causes turned out to be live **4.2** defects that only the 5.0 suite
> executed, not Rails 5 incompatibilities. The stage B write-up in the
> [plan](phase-4-implementation-plan.md) has the detail; the one item still owed is B.2, the
> broken `version_conflict_error` partial, which B.1 made unreachable without fixing.

**Characterize before fixing.** Every one of these is a Rails 5 behaviour difference in
application code, so the first question is always "what does 4.2 do here, and is that asserted
anywhere?" A fix that makes 5.0 green by changing 4.2 behaviour is a regression in what currently
ships.

- [x] **The cluster — content updates do not persist on 5.0. 7 of the 10, and the only one worth
  attacking first.** ✅ **Stage B.1 — all seven cleared by one fix.** The diagnosis held: one optimistic-locking difference under all four masks. 4.2's `touch` incremented `lock_version` from a stale value and 5.0's raises; `sync_locking_column_before_touch` re-reads it. ⚠️ **This does not make optimistic locking work** — a genuinely stale save still overwrites a concurrent edit, on both versions, and that defect is characterized rather than fixed (D6). It wears four masks: 2× `ActiveRecord::StaleObjectError` on `Cms::Page`
  (unit), 2× `Missing partial cms/shared/_version_conflict_error` (functional), 2×
  `manage_images.feature` and 1× `sitemap/pages.feature:19` (cucumber). One optimistic-locking
  difference underneath all four. Phase 3 ruled it out against its own single behaviour change
  with a control run, so it is pre-existing. **Diagnose the locking difference first** — the
  other three masks are downstream of it.
  - ⚠️ **Read the `manage_images` failures carefully: the step definitions have expected and
    actual reversed** ([`image_steps.rb:1-9`](../../features/step_definitions/image_steps.rb#L1)).
    Decoded, they say the update did not take.
- [x] **Fix the missing partial — and note it is broken on 4.2 too.** ✅ **Stage G**, held back from stage B deliberately so it could not be mistaken for the cluster fix. ⚠️ **There were two broken references in that file, not one** — `version_conflict_diff` on line 23 is broken the same way, and fixing only the one named here would have moved the failure down eighteen lines. Both now point at `cms/application/`. The branch is unreachable through ordinary use, so the characterization test raises the `StaleObjectError` the controller declares it rescues and lets everything downstream run for real.
  [`_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2) renders
  `cms/shared/version_conflict_error`; the file that exists is
  `app/views/cms/application/_version_conflict_error.html.erb`. 4.2 never takes the branch, so
  the bug has been latent. **This is a real bug independent of the upgrade** and it is worth
  fixing on its own merits — but it is a *symptom of a symptom* here, so fixing it will not make
  the functional failures pass, only change what they say. Characterize the branch so it stops
  being invisible.
- [x] **`PublishableTestCase#test_publish_on_save`** (unit) — `Expected false to be truthy`. ✅ **Stage B.4, and it was B7 in disguise.** `publish!` called `quote_value` with one argument against 4.2's two-parameter version; `publish`'s `rescue Exception` swallowed the ArgumentError, so publishing a non-versioned record silently did nothing for years — and this test had been edited to agree with the bug. The assertion is inverted back, with the history beside it.
  Survives from Phase 2's §5. Worth re-reading now that `save!` forwards `(*args, &block)`
  ([Phase 3 §5](phase-3-report.md)).
- [x] **`Cms::TasksControllerTest#test_complete_no_tasks`** (functional) — ✅ **Stage B.3, and this document was right that it was a class rather than a singleton.** Nine sites, not one; six fixed. ⚠️ The cause was not the integer cast — it is a **truthiness** bug: `if params[:some_id]` is true for a blank string, so a real `?some_id=` request was a 500 on **4.2 as well**. ⚠️ One of the nine (`toolbar_controller.rb:14`) turned out in stage F to be unreachable code.
  `PG::InvalidTextRepresentation: invalid input syntax for type integer: ""`. Rails 5 stopped
  coercing `""` to nil on integer casts. This is a **Tier B silent-change item in disguise**:
  characterize what the controller should do with a blank id before changing the cast, because
  every other blank-integer param in the engine has the same exposure.
- [x] **`features/portlets/portlets_with_params.feature`** (cucumber) — the portlet renders the
  page layout instead of its own `"I worked"` content. ✅ **Stage B.5 — this was B9.** An `ActionController::Parameters`-vs-`Hash` break, found by the cucumber failure rather than by the B9 audit.
- [x] **Watch `PortletTest#test_.blacklist`.** It passes, but it compares a class list whose order
  depends on load order. Treat it as flaky rather than fixed; if it is going to be relied on as a
  gate, make it order-independent. ✅ **Stage B.6, and it was worse than flaky** — `Cms::Portlet.blacklist` memoizes into `@blacklist`, so anything touching it earlier in the run meant the test's stub never applied and it asserted against real configuration. Cleared on both sides of the test; verified across seeds 1, 2, 3 and 7. A job green only on lucky orderings is not green, so this had to close before criterion 13 could be claimed.

### 4.1 — `belongs_to` required by default (B5) — highest confidence per hour

**⚠️ Set `config.active_record.belongs_to_required_by_default = true` in the test environment first.** BrowserCMS is an engine with no `load_defaults` of its own, so tests written against the dummy app's inherited defaults pass whether or not the declarations are correct. Without this, the whole item quietly tests nothing.

> ⚠️ **This instruction cannot be followed, and stage D established why.** The flag is read at **class-definition time**, so setting it in a `setup` block is a no-op on 5.0, and the accessor does not exist at all on 4.2. The concern behind it is real and is met a different way: the audit is made falsifiable instead — adding an unaudited `belongs_to`, contradicting a verdict, or moving the count each fails a test. See criterion 3 below and D1 in the [plan](phase-4-implementation-plan.md).

- [x] For each of the **29** declarations, one test that either (a) asserts the association is required, or (b) asserts a record saves without it. Mechanical, fast, and it forces a decision on all 29. ✅ **Stage D.** [`belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb), 11 tests, enumerating by **reflection** rather than a fixed list so a declaration added tomorrow is caught, plus a count tripwire asserting `24 literal + 3 behavior-injected + 2 dynamic = 29`.
- [x] Pay particular attention to the 5 injected by behaviors — they apply to every model using the mixin. ✅ **Stage D**, and they are checked **where they land** rather than on the behavior module. The genuinely missing one was dynamic: [`dynamic_attributes.rb:171`](../../lib/cms/behaviors/dynamic_attributes.rb#L171) runs once per portlet subclass against the same `CmsPortletAttribute`, so that class accumulates one `belongs_to` per portlet type — four here, plus one for every portlet a consuming project defines.
- [x] Note the existing `userstamping` tests cover only the *nil-user* cases, so under required-by-default they go red immediately. That is the one place this flag fails loudly, and it's an accident of a coverage gap rather than a designed net. Don't rely on the accident; write the explicit assertions. ✅ **Stage D — the explicit assertions exist**, and the advice not to rely on the accident turned out to be load-bearing for a reason this document did not anticipate: the flag cannot be set at all, so the loud failure could never have happened. `created_by` and `updated_by` are audited as `:optional` with the reason recorded (nil for anything created outside a request — seeds, rake tasks, migrations).

### 4.2 — Eager-load / autoload contract (B10) — one test, one hour, enormous signal

> ⚠️ **Written in stage C, deferred from the suite.** `eager_load!` succeeds on both bundles.
> The payload is the path→constant sweep: 128 engine files, **one Zeitwerk violation** —
> `app/portlets/helpers/cms/list_portlet_helper.rb` defines a bare `ListPortletHelper` where
> the path implies `Helpers::Cms::ListPortletHelper`. A hard 6.0 boot failure, recorded in the
> test's `KNOWN_ZEITWERK_MISMATCHES` rather than fixed, because naming is 6.0 work.
>
> Also measured: `engine.rb:112-116`'s nine `autoload_paths` pushes are **at most one**
> additive — two point at empty or missing directories and the rest duplicate paths Rails
> already globs. That shrinks the 6.0 estimate considerably.

- [x] `Rails.application.eager_load!`, then assert every expected `Cms::` constant resolves. ✅ **Written in stage C, enabled in stage F.** [`eager_load_test.rb`](../../test/unit/eager_load_test.rb), 4 tests, both bundles.
- [x] One test, and it catches an entire class of autoload regressions. ✅ It is four, and the valuable one is not the eager-load call — that succeeds on both bundles. It is the **path→constant sweep**: 128 files across 6 roots, one violation, recorded in `KNOWN_ZEITWERK_MISMATCHES` so the list cannot quietly grow. Proven in both directions.
- [x] **Do this even though Zeitwerk lands at 6.0, not 5.0.** ✅ **And the cost/benefit landed differently than expected in both directions.** The benefit: `engine.rb:112-116`'s nine `autoload_paths` pushes are **at most one** additive, so the 6.0 estimate shrinks considerably. The cost: `eager_load!` loads files no suite otherwise touches, which widened the coverage denominator and forced the branch gate to be re-baselined in stage F rather than the test being skipped. Original text follows. It is the cheapest possible defence against the largest single item in the whole upgrade — `lib/cms/engine.rb` is 135 lines with a 7-line test containing 1 assertion, and it pushes 6 directories onto `ActiveSupport::Dependencies.autoload_paths`, an API Zeitwerk does not have. This test's output will scope the 6.0 hop.

### 4.3 — `create_content_table` migration DSL (B3)

`lib/cms/extensions/.../schema_statements.rb` — 86.79%, 7 missed. It calls `create_table table_name, options, &block`, and the positional-options signature changes at Rails 5+.

- [x] A migration test calling `create_content_table` with each option combination (`versioned: true/false`, `name: true/false`), asserting the resulting column set on **both** the content table and the `_versions` table. ✅ **Stage E.** The DSL takes exactly two options, so the matrix is 2×2 and is enumerated in full in [`schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) (6 tests → 13), each case asserting the **complete** column set on both tables, plus the two asymmetries (`lock_version` content-only, `version_comment` versions-only) and the positional-options pass-through this item flags.
- [x] Blast radius is the largest in the codebase — every migration in BrowserCMS and in every downstream project. Currently nothing runs the DSL at all. ✅ It does now, on both bundles.

### 4.4 — `ActionController::Parameters` on the four uncovered sites (B9)

Ten sites exist; **only four need tests.** The other six are on lines CI executes (`content_controller.rb:72` at 153 hits, `path_helper.rb:33-36` at 49) — a `Parameters`-vs-`Hash` break there raises in CI, so test budget belongs elsewhere.

- [x] `app/controllers/cms/form_fields_controller.rb:16` — `params[:form_field].delete(:form_id)`. **File is 0% covered.** ✅ **Stage F — 0% → 42.6%**, 5 tests.
- [x] `app/controllers/cms/forms_controller.rb:33` — `params[:form].delete(:new_entry)`. **File is 0% covered.** ✅ **Stage F — 0% → 72.7%**, 5 tests. Instantiating it revealed that the **Forms admin UI 500s**: `Cms::Form.path` does not exist and `is_addressable` is commented out. Characterized, not fixed.
- [x] `app/controllers/cms/pages_controller.rb:126-128` — `strip_visibility_params`; 3 of its lines are untested. ✅ **Stage F**, both directions.
- [x] `app/controllers/cms/sections_controller.rb:43` — `params[:section].delete('group_ids')`, inside the 9 missed lines. ✅ **Stage F**, both directions.
- [x] Assert the stripped key is absent from the resulting record. ✅ **Stage F** — [`parameters_authorization_test.rb`](../../test/functional/cms/parameters_authorization_test.rb) asserts the keys are absent from `params`, not merely ignored downstream, and asserts **both** directions on each: a test that only checks the restricted user passes if the strip runs unconditionally, and one that only checks the privileged user passes if it never runs. ⚠️ Ten sites were expected; an **eleventh** turned up at `content_block_controller.rb:275`, a 5.1 breakage found only because a 0%-coverage controller was finally instantiated. **These two are authorization logic** — `strip_visibility_params` and the `group_ids` deletion exist to stop a non-admin setting fields they shouldn't — so they sit on a security boundary, not just a compatibility one.

### 4.5 — Schema dumper guard (B1)

The version claim here is **unverified** — the skill has no entry for `ColumnDumper` or `column_spec`. That is exactly why the guard test is the right response: it converts an unknown into a loud failure at whichever hop it lands.

- [x] A guard test that **fails loudly if `ActiveRecord::ConnectionAdapters::ColumnDumper` is not already defined** when `lib/cms/extensions/.../schema_dumper.rb` loads. Reopening a vanished module silently defines a new empty one — no error, no warning, patch gone. ⚠️ **Stage A — met as amended, because the guard as written would not have caught the real bug.** `ColumnDumper` still exists on 5.0; what changed is `column_spec`'s **arity**, and the patch was overriding it with a signature Rails no longer calls. The guard asserts the signature contract instead, and was seen red in both directions. See D3 and 1.5 in the [plan](phase-4-implementation-plan.md).
- [x] An end-to-end test: dump the schema for a table with boolean defaults, assert the output contains `published` / `deleted` / `archived` with their defaults. **Assert on the dumped output, not on `column_spec`'s return value** — the point is to detect the patch going missing. ✅ **Stage A.** [`schema_dumper_test.rb`](../../test/unit/schema_dumper_test.rb), 6 tests, both bundles. Its header names the three weaker shapes that pass against the broken dumper — "does not raise" and "output is non-empty" among them — so they are rejected on the record rather than by omission.
- [x] Why this ranks despite only 3 missed lines: the file's own comment documents this failure already happening once, producing a `db/schema.rb` missing half its tables. ✅ **It was happening again, right now.** Stage A measured a real dump on the 5.0 bundle: **0 of 74 tables emitted, exit status 0.** This was reprioritised to run first in the phase for that reason. Original text follows. A silently-truncated schema corrupts every developer's database and every CI run downstream, and it looks like a working build.

### 4.6 — Callback ordering audit (B6) — read before you write

`lib/cms/behaviors/versioning.rb` is 96.91% covered with 162 relevant lines. The risk isn't "untested," it's "tested for the wrong thing" — line coverage cannot tell you whether anything asserts that versioning happens in the right order *relative to* validation and dirty-tracking. Lines 206–225 are a comment block documenting an **observed** ActiveRecord `save` call order, and Rails 5 changed callback halting.

- [x] Read `test/unit/behaviors/versioning_test.rb` and `publishing_mini_test.rb` and answer three questions: does anything assert that a failed validation produces **no** new version? That `version_comment` reflects the changes from *this* save? That a rolled-back transaction leaves no orphan version row? — **none of the three had an assertion.** Answered by grep in a minute, not a day; the reading budget was the wrong half of the job
- [x] Write whichever of those is missing. Budget reading time before writing time. — all three written, 14 tests. Two behaviours were correct all along and are now guarded; `version_comment` is wrong on the CMS edit path, and the one-line cause is located in stage G of the [plan](phase-4-implementation-plan.md)

### 4.7 — The remaining Tier B items (can trail the bump)

- [x] **B2 — `dynamic_attributes` attribute chain.** ✅ **Done in stage H**, 10 tests in [`dynamic_attributes_chain_test.rb`](../../test/unit/behaviors/dynamic_attributes_chain_test.rb). Every question answered, and three answered **no**: `read_attribute` and `_read_attribute` do **not** both resolve dynamic attributes (only the wrapper is aliased, and it is private on these models and returns `nil` when called); `respond_to?` does **not** agree with `method_missing`, so `try` returns nil for an attribute that works; and `nonversioned_class` raises `FrozenError` in the only case it exists for. Round-trips through `save`/`reload`, `assign_attributes` and `[]=` do all hold. Version-agnostic as predicted — identical on both bundles. **This item was missing from the implementation plan and was recovered from this document.**
- [x] **B7 — `publishing.rb` hand-built SQL.** ✅ **Done in stage H**, 8 tests in [`publishing_sql_test.rb`](../../test/unit/behaviors/publishing_sql_test.rb), every assertion read back with `SELECT`. The insistence on a fresh query is load-bearing: `publish!` sets `self.published = true` in memory whatever the SQL did. Also covers the draft's values reaching the live row, no new version row, a no-op publish writing nothing, and the interpolated `WHERE` touching only its own row. One characterization: `publish` returns false rather than raising a programming error.
- [x] **B8 — `soft_deleting.rb` default scope.** ✅ **Done in stage H**, 10 tests in [`soft_deleting_test.rb`](../../test/unit/behaviors/soft_deleting_test.rb), targeting what `content_block_test.rb` does not already cover: that the startup `rescue` did not swallow the scope, composition in both chaining orders, `delete_all` not deleting, and the alias ordering that keeps `delete_all!` real. One characterization: `Model.exists?` with no arguments raises. ⚠️ **The `or` half cannot be written in this phase** — `ActiveRecord::Relation#or` arrives in Rails 5.0, so a test using it cannot pass on the `Gemfile` bundle and criterion 11 forbids version branching. Measured on 5.0 (the scope distributes correctly across both sides) and handed to Phase 5 with the answer attached.
- [ ] ⚠️ **NOT DONE — deliberately out of scope for Phase 4.** This document scopes B4 to validation tests only, with no replacement, and the [plan](phase-4-implementation-plan.md)'s stage H records the decision not to start it. Carry it forward. **B4 — the three untested Paperclip validation macros.** `validates_attachment_size` (9 missed), `validates_attachment_content_type` (6), `validates_attachment_presence` (3). One passing and one failing test each, pinning the current error messages. These become the acceptance criteria for whatever replaces Paperclip. ⚠️ `validates_attachment_presence` is **defined twice** — `attaching.rb:89` and `:98`; the first is dead code silently overwritten.
- [x] ✅ **Done in stage I**, 12 tests across [`error_branches_test.rb`](../../test/functional/cms/error_branches_test.rb) and [`section_nodes_controller_test.rb`](../../test/functional/cms/section_nodes_controller_test.rb) — the latter being the first coverage `move_to_position` has ever had. This item was **missing from the implementation plan entirely**, the second lost that way after B2, and was recovered during the stage-H checkbox audit. The *fixes* had already landed in Phase 3; what was missing was the tests, and each asserts the **content type** as well as the status, because `render text:` answers `text/html` and `render plain:` answers `text/plain` — a status-only assertion would not have noticed a reversion of the 5.1-critical conversion. The `move_to_position` dedupe was **fixed** rather than characterized (D8 in the plan), after reading the front-end consumer and finding it idempotent. Three further defects surfaced and are characterized: the `move_to_position` rescue cannot report either lookup failure, `form_fields_controller#update` cannot fail at all, and — separately, in code this phase never touched — `Cms::Section#pages` returned rows in arbitrary order (D9, fixed).

---

## Exit criteria

| # | Criterion | How to verify |
|---|---|---|
| 1 | Suite green on both Gemfiles | CI both jobs passing |
| 2 | Coverage is **at or above** the Phase 2 number, with branch coverage reported | ⚠️ **Met on line, re-baselined on branch.** Line **78.44% → 83.54%**. Branch **70.89% → 70.49%**, and `COVERAGE_MINIMUM_BRANCH` moved to match — the numerator never fell; the eager-load test widened the denominator by six files no suite had ever loaded, so the old figure was measured over a universe that excluded six untested controllers. Reasoning recorded beside the threshold in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake) and in stage F of the [plan](phase-4-implementation-plan.md) |
| 3 | ~~`belongs_to_required_by_default = true` is set in the test environment~~ → **the audit is falsifiable** | ✅ **Met in stage D, as amended.** The original cannot be met: the flag is read at class-definition time, so a setup block is a no-op on 5.0, and the accessor does not exist on 4.2. Replaced by the property it was reaching for — adding an unaudited `belongs_to`, contradicting a verdict, or moving the count each fails a test. See D1 in the [plan](phase-4-implementation-plan.md) |
| 4 | All 29 `belongs_to` declarations have an explicit test: required, or saves-without-it | ✅ **Met in stage D.** [`belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb), 11 tests, enumerating by **reflection** rather than a fixed list so a declaration added tomorrow is caught. The count assertion makes this criterion literally true: 24 literal + 3 behavior-injected + 2 dynamic = 29 |
| 5 | An eager-load test exists and passes | ✅ **Met in stage F.** [`eager_load_test.rb`](../../test/unit/eager_load_test.rb) runs in the default suite on both bundles. Written in stage C and held out until the branch baseline was re-measured rather than worked around |
| 6 | `create_content_table` is exercised with every option combination | ✅ **Met in stage E.** The DSL takes exactly two options, so the matrix is 2×2 and is enumerated in full in [`schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) (6 tests → 13). Each case asserts the **complete** column set on both tables, plus the two asymmetries (`lock_version` content-only, `version_comment` versions-only) and the option pass-through to `create_table` that B3 flags |
| 7 | The four uncovered `Parameters` sites have tests; `form_fields_controller.rb` and `forms_controller.rb` are **no longer 0%** | ✅ **Met in stage F.** `form_fields_controller` **0% → 42.6%**, `forms_controller` **0% → 72.7%**; functional tests 89 → 122. Both authorization sites assert **both** directions, and an **eleventh** B9 site was found at `content_block_controller.rb:275` (a 5.1 breakage). Three live defects surfaced and were characterized — see stage F |
| 8 | A guard test fails if `ColumnDumper` is undefined at load time | ⚠️ **Met in stage A, as amended.** The constant is *not* undefined on 5.0 — `ColumnDumper` still exists; `column_spec`'s arity changed underneath it, which the criterion as written would not have caught. The guard asserts the **signature contract** instead, and was seen red in both directions. See D3 and 1.5 in the [plan](phase-4-implementation-plan.md) |
| 9 | Schema dump output is asserted end-to-end for boolean-default columns | ✅ **Met in stage A.** [`schema_dumper_test.rb`](../../test/unit/schema_dumper_test.rb), 6 tests green on both bundles, asserting dumped **content**. Its header names the three weaker shapes that pass against the broken dumper — "does not raise" and "output is non-empty" among them — so they are rejected on the record rather than by omission |
| 10 | The B6 audit is **written down**, with the three questions answered yes/no | ✅ **Met in stage G.** All three assertions were **absent**; all three are now written, 14 tests in [`versioning_call_chain_test.rb`](../../test/unit/behaviors/versioning_call_chain_test.rb), whose header carries the answers. Two behaviours turned out correct-but-unguarded. The third does **not** hold on the CMS edit path: `build_object_from_version` clears the wrong object's dirty state, so every version saved through the admin UI is commented with the whole record. Characterized, not fixed — see stage G |
| 11 | Every new test is a *characterization* test | Each asserts current behaviour with no `NextRails.next?` branching: `grep -rn "NextRails" test/ spec/` stays empty |
| 12 | No test was written for a loud failure | Review: no new test exists solely to catch `*_filter`, `update_attributes`, or `File.exists?` — the boot sequence catches those |
| 13 | **The gating `next-rails` job is green** *(arrived from [Phase 3](phase-3-backwards-compatible-fixes.md), where it was criterion 16)* | ✅ **Met in stage B.** All ten resolved, plus an order-dependent flake that would have made the job green only on lucky seeds. Verified across seeds 1, 2, 3 and 7 |
| 14 | **Each of the ten was characterized before it was fixed** *(added after Phase 3)* | ✅ **Met in stage B.** Every fix has a test passing on the `Gemfile` bundle. Note three of the four causes were 4.2 defects, so those tests assert *corrected* behaviour on both bundles rather than pinning 4.2 — called out per-item in the plan rather than blurred |

**Done means:** criteria 3+4 hold together (the flag is on *and* all 29 are asserted), criterion 8's guard has been proven to guard by deliberately breaking it, the two 0%-coverage Forms controllers are no longer at zero, and **criterion 13 has flipped the `next-rails` job green** — which is also what unblocks [Phase 0](phase-0-baseline-and-ci.md)'s criteria 1–2.

> **Criterion 8 deserves emphasis.** A guard test that has never been seen to fail is not a guard. Break the constant, watch it go red, put it back.

---

## Explicitly not in this phase

- **No Rails bump.** Still 4.2.11.3.
- **No coverage-driven test writing.** The `TEST_COVERAGE_PLAN.md` coverage-per-effort backlog is a *later* activity, pursued as regression pressure demands. Writing tests to raise a percentage is the wrong objective here — every test in this phase exists to detect a specific silent semantic change.
- **No tests for loud breakage** (criterion 12). `*_filter`, `update_attributes`, `File.exists?`, `render text:` as such — all fail at boot or raise immediately. Only their *behavioural* edges get tests.
- **Not testing the six covered `Parameters` sites.** CI is already the detector.
- **No Paperclip replacement**, only the validation tests that will constrain it later.
- **No content-block lifecycle integration specs.** The single most valuable test asset — create → edit → publish → connect → render → version → revert in one chain — is a `cms`-side deliverable and is out of scope for these files. See [`TEST_COVERAGE_ANALYSIS.md` Phase 3](../../TEST_COVERAGE_ANALYSIS.md).
- **No helper tests** (11 untested, including the 168-line `ui_elements_helper.rb`). Real gaps, but not silent-Rails-5-change gaps.
