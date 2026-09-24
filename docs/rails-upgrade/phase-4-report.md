# Phase 4 — Report

**Implements:** [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md)
**Plan:** [`phase-4-implementation-plan.md`](phase-4-implementation-plan.md)
**Entry state:** `00c5e5b1` — 4.2 green at 1007 tests / 78.44% line / 70.89% branch, cucumber 154/154; `Gemfile.next` red with ten failures inherited from Phase 3.

---

## 1. Headline

**Both bundles are green and identical for the first time in the upgrade.** The gating `next-rails` job passes, which unblocks Phase 0's criteria 1 and 2 and lets this work merge.

| | Entry (Phase 3) | Exit (Phase 4) |
|---|---|---|
| 4.2 unit | 793 | **838** |
| 4.2 spec | 145 | 145 |
| 4.2 functional | 88 | **139** |
| 4.2 orphan | 7 | 7 |
| 4.2 cucumber | 154 / 154 | **154 / 154** |
| 5.0 | **10 failures** | **identical to 4.2, 0F / 0E** |
| line coverage | 78.44% | **83.94%** |
| branch coverage | 70.89% | **70.97%** ([§5](#5-the-coverage-gate-moved-three-times)) |

**13 of 14 criteria met; two of those as amended, and the amendments are the interesting part.** ⚠️ Criterion 1 carries a caveat about suite stability — [§6](#6-an-open-question-suite-stability).

But the headline number is not the point of this phase, and reporting it as one would misrepresent what happened.

## 2. What this phase was actually for, and what it found

Phase 4 was scoped to write characterization tests: pin what the code does *today* so that Rails 5's silent semantic changes cannot slip past. The expectation was that the work would be about Rails 5.

**It was not.** Of the four root causes behind the ten red tests, **three were live defects on the 4.2 bundle that ships** — they had simply never been executed. The 5.0 suite executed them. And once the phase started instrumenting code that had never been instrumented, the same pattern repeated at every stage:

| Defect | Stage | Fails on 4.2? |
|---|---|---|
| The schema dumper emitted **0 of 74 tables and exited 0** on the 5.0 bundle | A | 5.0 only — but silently |
| Optimistic locking silently defeated on every versioned content type | B | **yes** |
| Publishing a non-versioned record silently did nothing for years | B | **yes** |
| `?some_id=` blank in a URL was a 500 | B | **yes** |
| The edit-conflict screen raised `MissingTemplate` — two broken partial paths, not one | G | **yes** |
| Public form submission 500s for every form showing confirmation text | F | **yes** |
| The Forms admin UI 500s | F | **yes** |
| `Cms::ToolbarController` is routed but can never render | F | **yes** |
| Every version saved through the CMS is commented with the whole record | G | **yes** |
| `Model.exists?` with no arguments raises on every soft-deleting model | H | **yes** |
| `read_attribute` returns **nil** on every portlet instead of raising | H | **yes** |
| `nonversioned_class` raises `FrozenError` in the only case it exists for | H | **yes** |
| `move_to_position`'s rescue cannot report either lookup failure | I | **yes** |
| `form_fields_controller#update` cannot fail at all | I | **yes** |
| `Cms::Section#pages` returned rows in arbitrary order | I | **yes** |

**Fourteen of the fifteen fail identically on Rails 4.2.** None was caused by the upgrade. The upgrade was the excuse to look.

That is the finding worth carrying out of this phase: **the dual-boot suite is not a Rails 5 canary, it is a second execution of the codebase under different semantics, and it found more 4.2 bugs than 5.0 ones.** That argument is now recorded in [`ci.yml`](../../.github/workflows/ci.yml) as the reason to keep the job gating after it went green.

## 3. What was fixed, and what was deliberately left

**Fixed** — every one preserving what 4.2 does for a user today, which is the line [D6](phase-4-implementation-plan.md) drew and [D8](phase-4-implementation-plan.md) restated:

- the schema dumper patch, guarded on `ActiveRecord::VERSION::MAJOR`
- the locking cluster, by re-reading the locking column before the after-save touch
- six blank-param 500s (three more were recorded rather than changed — [D5](phase-4-implementation-plan.md))
- `quote_value` → `connection.quote`
- three `ActionController::Parameters` coercions, one of which was a 5.1 breakage
- both broken `version_conflict` partial paths
- the `move_to_position` dedupe ([D8](phase-4-implementation-plan.md))
- `Cms::Section#pages` ordering ([D9](phase-4-implementation-plan.md))

**Left standing, each characterized by a test that fails when it is repaired:**

| Defect | Why not fixed |
|---|---|
| ~~Optimistic locking still silently overwrites concurrent edits~~ **— fixed by CMS-435** | Making conflicts raise changes 4.2 behaviour on the engine's busiest path. A product decision ([D6](phase-4-implementation-plan.md)) — taken, and the answer was to raise. [cms-435-optimistic-locking.md](cms-435-optimistic-locking.md) |
| `version_comment` names every field on the CMS edit path | The one-word fix also switches on a skip-save branch that has never run in any released version |
| `publish` swallows `Exception`, including programming errors | Narrowing it changes every save of every content type |
| `Model.exists?` with no arguments raises | The override also answers with `count > 0` rather than `LIMIT 1`; "fixing" the signature commits every caller to a full count |
| `read_attribute` private and answering nil on portlets | Changes the public surface of every portlet class in every installation |
| `respond_to?` disagrees with `method_missing` | A correct `respond_to_missing?` would have to return true for every name |
| `nonversioned_class` raises `FrozenError` | Unreachable in this engine; the repair enables a path that has never run anywhere |
| Public form submission and the Forms admin UI 500 | Both need a product decision about the Forms subsystem's abandoned addressable migration |
| `Cms::ToolbarController` is vestigial | Deleting a routed controller is the admin UI owner's call |
| `move_to_position`'s rescue raises on lookup failure | The repair means deciding what the error says without the objects that failed to load |

**Each of these is a ticket someone has to write.** The tests are the specification: when the behaviour is repaired, the test goes red and names what to do.

## 4. Where the phase documents were wrong

Both were written before anything ran, and measurement moved them. That is the process working, but it is worth recording plainly.

**Two criteria could not be met as written:**

- **Criterion 3** asked for `belongs_to_required_by_default = true` in the test environment. The flag is read at class-definition time, so a setup block is a no-op on 5.0, and the accessor does not exist on 4.2. Replaced by the property it was reaching for: the audit is *falsifiable* ([D1](phase-4-implementation-plan.md)).
- **Criterion 8** asked for a guard that fails if `ColumnDumper` is undefined. It still exists on 5.0 — only `column_spec`'s arity moved, so the guard as specified would not have caught the actual live bug. It asserts the signature contract instead ([D3](phase-4-implementation-plan.md)).

**The implementation plan dropped two work items**, both recovered by checking stages against the phase document rather than against the plan:

- **B2**, the `dynamic_attributes` chain — recovered in stage H, and the most productive of that stage's three items.
- **Tier C's error branches** — recovered in the stage-H checkbox audit and folded into stage I.

This is the argument for the [three-document split](README.md) stated concretely: **the phase file is the contract, the plan is one approach to it.** Had the audit gone the other way, both items would have vanished with no record.

**Three diagnoses in the phase document were wrong in instructive ways:**

- The `tasks_controller` failure was filed as a single integer-cast bug. It was a **truthiness** bug and there were nine sites.
- The missing partial was filed as one broken reference. There were two, and fixing only the named one would have moved the failure eighteen lines down and looked like a fix.
- `B6`'s audit was budgeted a day of reading. It took a minute of `grep` — the budget was on the wrong half of the job, which was running the questions rather than reading for them.

**And one correction to this phase's own reasoning**, caught in review: an earlier draft of [D8](phase-4-implementation-plan.md) claimed "a behaviour change to the shipping 4.2 bundle is not Phase 4's to make." The record contradicts it — stage B changed 4.2 behaviour ten times. The rule actually applied is narrower: *does anyone's working behaviour change?* A crash is not a behaviour anyone depends on. Correcting it flipped the recommendation from characterize to fix.

## 5. The coverage gate moved three times

Recorded because a future reader will see a **lowered** quality gate in the history and assume a regression.

| | branch | why |
|---|---|---|
| Phase 3 exit | 70.83% | |
| Stage F | **70.49%** | The eager-load test widened the **denominator** by six files no suite had ever loaded. The numerator never fell |
| Stage H | **70.63%** | B2/B7/B8 tests |
| Stage I | **70.97%** | Tier C tests |

The stage F drop is the one that matters: **nothing became less tested.** The old 70.83% was measured over a universe that silently excluded six untested controllers — one of them `form_entries_controller`, 108 lines at 0%, handling **public, unauthenticated form submission**. Line coverage moved the other way for the same reason, 78.44% → 83.54%.

Closing it honestly was attempted first, and got to 70.50%. The last five branches are in a controller with **zero routes** and in view branches needing invented fixtures — which is what the phase document rules out. Full reasoning sits beside `COVERAGE_MINIMUM_BRANCH` in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake).

## 6. An open question: suite stability

**Criterion 1 is met, but not unconditionally, and the caveat belongs in the record rather than in someone's memory.**

Across roughly **14 full `ci:test` runs** during stage I, **two failed** — each on a different pre-existing unit test, neither touched by this phase:

| Test | Failure | Status |
|---|---|---|
| `sitemap_test.rb` `"pages"` | two pages returned transposed | **Cause found and fixed** — [D9](phase-4-implementation-plan.md). `Cms::Section#pages` was the only reader on its class with no `ORDER BY` |
| `versioning_test.rb` `"Updating a block should increment the version on the new draft"` | `block.versions.size` was 1, expected 2 | **Not isolated.** Not reproducible in 15+ subsequent runs, in isolation or under forced ordering |

What was ruled out for the second one: it is not machine load (the units suite finished in 44.2s on the failing run and 45.2–45.8s on passing ones), and it is not pollution from this phase's new tests (`ActiveSupport::TestCase` rolls every unit test back in a transaction).

What is *suspected* and unproven: the units suite runs **two database-cleaning strategies in one process.** `ActiveSupport::TestCase` rolls back, while [`publishing_mini_test.rb`](../../test/unit/behaviors/publishing_mini_test.rb) is a `Minitest::Spec` — inside the units glob — that calls `DatabaseCleaner.clean` with the `:truncation` strategy after **every example**. [`test_helper.rb:42-52`](../../test/test_helper.rb#L42) already documents this exact arrangement causing tests to "pass or fail on that coin flip depending purely on where the random test order happened to put the first spec". That was mitigated by truncating once at load; the mitigation evidently narrowed the window rather than closing it. Forcing the spec-then-transactional order did not reproduce the failure, so this remains a hypothesis.

**This is pre-existing and not a Phase 4 regression**, but it should not be inherited silently. A suite that fails one run in seven is not green, it is *mostly* green, and the difference matters most at exactly the moment a bump makes everyone suspicious of every red build. **Recommendation for Phase 5: resolve the mixed-strategy arrangement before the bump**, so that a red `next-rails` job during the bump means what it says. One spec file is the entire exposure.

## 7. On sabotage

Every fix and every characterization in this phase was verified by breaking the code and watching the test go red. Roughly thirty sabotages. **Three did nothing**, and each was instructive:

- A `sed` that silently failed to match, making it look as though stage E's tests missed a planted defect.
- A sabotage applied to a branch `Cms::HtmlBlock` does not take.
- Removing a `private` keyword that turned out to be **dead code** — `alias_method` copies the visibility of its *target*, not the ambient default, so the line every reader would blame has no effect. That one corrected a claim already written into a test file.

Hence the rule adopted mid-phase and applied for the rest of it: **verify that a sabotage took effect before believing its result.** A sabotage that silently does nothing is indistinguishable from a test that does nothing.

## 8. Not done

- [ ] **B4 — the three untested Paperclip validation macros.** Deliberately out of scope: the phase document scopes it to validation tests with no replacement. ⚠️ It needs a destination in the Phase 5 or Phase 6 document rather than lapsing here. `validates_attachment_presence` is also **defined twice** (`attaching.rb:89` and `:98`), the first silently overwritten.
- [ ] **The `or` half of B8.** `ActiveRecord::Relation#or` arrives in Rails 5.0, so a test using it cannot pass on the `Gemfile` bundle and criterion 11 forbids version branching. Measured on 5.0 — the default scope distributes correctly across both sides — and handed to Phase 5 with the answer attached.
- [ ] **The ten characterized defects in [§3](#3-what-was-fixed-and-what-was-deliberately-left).** Each needs a ticket and a product decision. The two worst are public form submission 500ing for unauthenticated visitors, and optimistic locking being silently defeated.
  - ✅ **Optimistic locking — closed by CMS-435 (2026-09-24).** A stale versioned save now raises, gated on the caller having supplied `lock_version`. The characterization test was deleted as designed. This phase saw one defect where there were three; the write-up is [cms-435-optimistic-locking.md](cms-435-optimistic-locking.md).

## 9. For Phase 5

Phase 5 is the bump itself. Three things from here bear on it:

1. **The `next-rails` job should stay gating.** It is green now, and the argument for keeping it is in [`ci.yml`](../../.github/workflows/ci.yml): it has found more 4.2 bugs than 5.0 ones.
2. **`form_entries_controller` is on Phase 5's manual-verification list** and now has 10 tests, which replaces part of that manual pass with something that runs every build. It is also where the most serious open defect lives.
3. **Two 5.1 landmines are now covered rather than merely converted:** `render text:` at two sites and the two-argument `connection.quote` in `publishing.rb`. The tests assert behaviour rather than API shape, so they survive the removal and fail only if the fix for it is wrong.

The Zeitwerk inventory from stage C also scopes **Phase 6**: one misnamed file, and an `autoload_paths` block in `engine.rb` that is at most one entry additive and can mostly be deleted.
