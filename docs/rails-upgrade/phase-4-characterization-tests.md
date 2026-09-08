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

### 4.0 — The ten Rails 5 failures inherited from Phase 3 *(added after Phase 3)*

**This item owns exit criterion 13 — turning the gating `next-rails` CI job green.** It arrived
here as [Phase 3's criterion 16](phase-3-backwards-compatible-fixes.md), which Phase 3 could not
close: it cleared every defect that was in its own scope and the job stayed red. What remains is
not mechanical, which is exactly why it belongs in the phase whose method is characterization.
Full diagnosis in [`phase-3-report.md` §6](phase-3-report.md#L402); the current failure list is
also in the [`next-rails` job comment](../../.github/workflows/ci.yml).

**The CI job stays gating and red until this item closes.** Two consequences to plan around:
every PR is red in the meantime, and [Phase 0](phase-0-baseline-and-ci.md)'s criteria 1–2 — a
green run on the default branch — cannot close until then either.

**Characterize before fixing.** Every one of these is a Rails 5 behaviour difference in
application code, so the first question is always "what does 4.2 do here, and is that asserted
anywhere?" A fix that makes 5.0 green by changing 4.2 behaviour is a regression in what currently
ships.

- [ ] **The cluster — content updates do not persist on 5.0. 7 of the 10, and the only one worth
  attacking first.** It wears four masks: 2× `ActiveRecord::StaleObjectError` on `Cms::Page`
  (unit), 2× `Missing partial cms/shared/_version_conflict_error` (functional), 2×
  `manage_images.feature` and 1× `sitemap/pages.feature:19` (cucumber). One optimistic-locking
  difference underneath all four. Phase 3 ruled it out against its own single behaviour change
  with a control run, so it is pre-existing. **Diagnose the locking difference first** — the
  other three masks are downstream of it.
  - ⚠️ **Read the `manage_images` failures carefully: the step definitions have expected and
    actual reversed** ([`image_steps.rb:1-9`](../../features/step_definitions/image_steps.rb#L1)).
    Decoded, they say the update did not take.
- [ ] **Fix the missing partial — and note it is broken on 4.2 too.**
  [`_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2) renders
  `cms/shared/version_conflict_error`; the file that exists is
  `app/views/cms/application/_version_conflict_error.html.erb`. 4.2 never takes the branch, so
  the bug has been latent. **This is a real bug independent of the upgrade** and it is worth
  fixing on its own merits — but it is a *symptom of a symptom* here, so fixing it will not make
  the functional failures pass, only change what they say. Characterize the branch so it stops
  being invisible.
- [ ] **`PublishableTestCase#test_publish_on_save`** (unit) — `Expected false to be truthy`.
  Survives from Phase 2's §5. Worth re-reading now that `save!` forwards `(*args, &block)`
  ([Phase 3 §5](phase-3-report.md)).
- [ ] **`Cms::TasksControllerTest#test_complete_no_tasks`** (functional) —
  `PG::InvalidTextRepresentation: invalid input syntax for type integer: ""`. Rails 5 stopped
  coercing `""` to nil on integer casts. This is a **Tier B silent-change item in disguise**:
  characterize what the controller should do with a blank id before changing the cast, because
  every other blank-integer param in the engine has the same exposure.
- [ ] **`features/portlets/portlets_with_params.feature`** (cucumber) — the portlet renders the
  page layout instead of its own `"I worked"` content.
- [ ] **Watch `PortletTest#test_.blacklist`.** It passes, but it compares a class list whose order
  depends on load order. Treat it as flaky rather than fixed; if it is going to be relied on as a
  gate, make it order-independent.

### 4.1 — `belongs_to` required by default (B5) — highest confidence per hour

**⚠️ Set `config.active_record.belongs_to_required_by_default = true` in the test environment first.** BrowserCMS is an engine with no `load_defaults` of its own, so tests written against the dummy app's inherited defaults pass whether or not the declarations are correct. Without this, the whole item quietly tests nothing.

- [ ] For each of the **29** declarations, one test that either (a) asserts the association is required, or (b) asserts a record saves without it. Mechanical, fast, and it forces a decision on all 29.
- [ ] Pay particular attention to the 5 injected by behaviors — they apply to every model using the mixin.
- [ ] Note the existing `userstamping` tests cover only the *nil-user* cases, so under required-by-default they go red immediately. That is the one place this flag fails loudly, and it's an accident of a coverage gap rather than a designed net. Don't rely on the accident; write the explicit assertions.

### 4.2 — Eager-load / autoload contract (B10) — one test, one hour, enormous signal

- [ ] `Rails.application.eager_load!`, then assert every expected `Cms::` constant resolves.
- [ ] One test, and it catches an entire class of autoload regressions.
- [ ] **Do this even though Zeitwerk lands at 6.0, not 5.0.** It is the cheapest possible defence against the largest single item in the whole upgrade — `lib/cms/engine.rb` is 135 lines with a 7-line test containing 1 assertion, and it pushes 6 directories onto `ActiveSupport::Dependencies.autoload_paths`, an API Zeitwerk does not have. This test's output will scope the 6.0 hop.

### 4.3 — `create_content_table` migration DSL (B3)

`lib/cms/extensions/.../schema_statements.rb` — 86.79%, 7 missed. It calls `create_table table_name, options, &block`, and the positional-options signature changes at Rails 5+.

- [ ] A migration test calling `create_content_table` with each option combination (`versioned: true/false`, `name: true/false`), asserting the resulting column set on **both** the content table and the `_versions` table.
- [ ] Blast radius is the largest in the codebase — every migration in BrowserCMS and in every downstream project. Currently nothing runs the DSL at all.

### 4.4 — `ActionController::Parameters` on the four uncovered sites (B9)

Ten sites exist; **only four need tests.** The other six are on lines CI executes (`content_controller.rb:72` at 153 hits, `path_helper.rb:33-36` at 49) — a `Parameters`-vs-`Hash` break there raises in CI, so test budget belongs elsewhere.

- [ ] `app/controllers/cms/form_fields_controller.rb:16` — `params[:form_field].delete(:form_id)`. **File is 0% covered.**
- [ ] `app/controllers/cms/forms_controller.rb:33` — `params[:form].delete(:new_entry)`. **File is 0% covered.**
- [ ] `app/controllers/cms/pages_controller.rb:126-128` — `strip_visibility_params`; 3 of its lines are untested.
- [ ] `app/controllers/cms/sections_controller.rb:43` — `params[:section].delete('group_ids')`, inside the 9 missed lines.
- [ ] Assert the stripped key is absent from the resulting record. **These two are authorization logic** — `strip_visibility_params` and the `group_ids` deletion exist to stop a non-admin setting fields they shouldn't — so they sit on a security boundary, not just a compatibility one.

### 4.5 — Schema dumper guard (B1)

The version claim here is **unverified** — the skill has no entry for `ColumnDumper` or `column_spec`. That is exactly why the guard test is the right response: it converts an unknown into a loud failure at whichever hop it lands.

- [ ] A guard test that **fails loudly if `ActiveRecord::ConnectionAdapters::ColumnDumper` is not already defined** when `lib/cms/extensions/.../schema_dumper.rb` loads. Reopening a vanished module silently defines a new empty one — no error, no warning, patch gone.
- [ ] An end-to-end test: dump the schema for a table with boolean defaults, assert the output contains `published` / `deleted` / `archived` with their defaults. **Assert on the dumped output, not on `column_spec`'s return value** — the point is to detect the patch going missing.
- [ ] Why this ranks despite only 3 missed lines: the file's own comment documents this failure already happening once, producing a `db/schema.rb` missing half its tables. A silently-truncated schema corrupts every developer's database and every CI run downstream, and it looks like a working build.

### 4.6 — Callback ordering audit (B6) — read before you write

`lib/cms/behaviors/versioning.rb` is 96.91% covered with 162 relevant lines. The risk isn't "untested," it's "tested for the wrong thing" — line coverage cannot tell you whether anything asserts that versioning happens in the right order *relative to* validation and dirty-tracking. Lines 206–225 are a comment block documenting an **observed** ActiveRecord `save` call order, and Rails 5 changed callback halting.

- [ ] Read `test/unit/behaviors/versioning_test.rb` and `publishing_mini_test.rb` and answer three questions: does anything assert that a failed validation produces **no** new version? That `version_comment` reflects the changes from *this* save? That a rolled-back transaction leaves no orphan version row?
- [ ] Write whichever of those is missing. Budget reading time before writing time.

### 4.7 — The remaining Tier B items (can trail the bump)

- [ ] **B2 — `dynamic_attributes` attribute chain.** Assert `read_attribute` **and** `_read_attribute` both resolve dynamic attributes; that `respond_to?` agrees with `method_missing`; that a dynamic attribute survives `save` → `reload` → read; round-trips through `assign_attributes` and `[]=`. Also cover `nonversioned_class`, which has no test. Worst test-to-source ratio in the repo (384 LOC / 73 test LOC). *Version claim unverified; the test is version-agnostic.*
- [ ] **B7 — `publishing.rb` hand-built SQL.** Assert `publish!` flips `published` in the database for versioned and non-versioned models, **read back through a fresh query**, not the in-memory object. *Version claim unverified; behavioural test survives being wrong about it.*
- [ ] **B8 — `soft_deleting.rb` default scope.** Assert `deleted` records are excluded by default, included under `unscoped`, and that the default scope composes correctly with `where` and `or`.
- [ ] **B4 — the three untested Paperclip validation macros.** `validates_attachment_size` (9 missed), `validates_attachment_content_type` (6), `validates_attachment_presence` (3). One passing and one failing test each, pinning the current error messages. These become the acceptance criteria for whatever replaces Paperclip. ⚠️ `validates_attachment_presence` is **defined twice** — `attaching.rb:89` and `:98`; the first is dead code silently overwritten.
- [ ] **Tier C fixes with a behavioural choice:** the two `render text:` error branches (`content_block_controller.rb:138` "Not Implemented", `form_fields_controller.rb:43` "Fail"/500) and `Relation#uniq` in `move_to_position`. Worth testing *because* they're error paths nothing exercises.

---

## Exit criteria

| # | Criterion | How to verify |
|---|---|---|
| 1 | Suite green on both Gemfiles | CI both jobs passing |
| 2 | Coverage is **at or above** the Phase 2 number, with branch coverage reported | Coverage artifact compared against Phase 2 |
| 3 | **`belongs_to_required_by_default = true` is set in the test environment** | `grep -rn "belongs_to_required_by_default" test/` returns a line — without this, criterion 4 is meaningless |
| 4 | All 29 `belongs_to` declarations have an explicit test: required, or saves-without-it | A test file enumerates them; the count in the test matches 29 |
| 5 | An eager-load test exists and passes | `Rails.application.eager_load!` appears in a test; it runs in the default suite, not a manual task |
| 6 | `create_content_table` is exercised with every option combination | Test asserts columns on both the content table and the `_versions` table |
| 7 | The four uncovered `Parameters` sites have tests; `form_fields_controller.rb` and `forms_controller.rb` are **no longer 0%** | Coverage report shows both files above 0% |
| 8 | A guard test fails if `ColumnDumper` is undefined at load time | Temporarily rename the constant in the patch file; the guard test must go red. **Verify the guard actually guards.** |
| 9 | Schema dump output is asserted end-to-end for boolean-default columns | Test asserts on dumped `db/schema.rb` content, not on `column_spec` |
| 10 | The B6 audit is **written down**, with the three questions answered yes/no | A committed note or test comments state which of the three assertions existed and which were added |
| 11 | Every new test is a *characterization* test | Each asserts current behaviour with no `NextRails.next?` branching: `grep -rn "NextRails" test/ spec/` stays empty |
| 12 | No test was written for a loud failure | Review: no new test exists solely to catch `*_filter`, `update_attributes`, or `File.exists?` — the boot sequence catches those |
| 13 | **The gating `next-rails` job is green** *(arrived from [Phase 3](phase-3-backwards-compatible-fixes.md), where it was criterion 16)* | All ten Phase 3 residue failures resolved (4.0). This is criterion 1's 5.0 half stated as the deliverable it is, because it is the one criterion here with a red CI job and a blocked merge path behind it |
| 14 | **Each of the ten was characterized before it was fixed** *(added after Phase 3)* | For every item in 4.0, a test asserts the **4.2** behaviour and passes on the `Gemfile` bundle. A fix that greens 5.0 by changing what 4.2 does is a regression in what ships — this criterion is what catches that |

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
