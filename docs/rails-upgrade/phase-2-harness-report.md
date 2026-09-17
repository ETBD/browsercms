# Phase 2 — Harness Migration Report

**Implements:** [`phase-2-harness-migration.md`](phase-2-harness-migration.md) via [`phase-2-implementation-plan.md`](phase-2-implementation-plan.md)
**Measured on:** Ruby 2.7.8, PostgreSQL 15, macOS. Rails 4.2.11.3 (`Gemfile`) and 5.0.7.2 (`Gemfile.next`).

This file is the record. Where it disagrees with the plan, this file is right and the
plan was written before the measurement existed.

---

## 1. Headline

| | Before (Phase 1) | After |
|---|---|---|
| **4.2 full suite** | exit 0 — 994 tests, 0F/0E; cucumber 154/154 | **exit 0 — 996 tests, 0F/0E; cucumber 154/154** |
| **4.2 line coverage** | 75.82% (simplecov 0.12) | **78.35% (simplecov 0.22)** — same 4901 covered lines, see [§4](#4-stage-f--the-coverage-number-moved-and-why-that-is-not-a-regression) |
| **4.2 branch coverage** | not measured | **70.79%** — reported, not gated |
| **5.0 unit suite** | 754 tests, 2F / **323E** | **756 tests, 2F / 3E** |
| **5.0 cucumber** | did not load | **154 scenarios collected**, 6 pass / 148 fail |
| **5.0 full suite** | red | **still red** — 5 application defects, see [§5](#5-what-still-blocks-rails-5-and-who-owns-it) |

The harness migration is **done**. Every remaining Rails 5 failure is application
behaviour, not test plumbing.

---

## 2. Exit criteria

| # | Criterion | Verdict |
|---|---|---|
| 1 | Coverage still reads the baseline on 4.2 | ✅ but **the baseline moved to 78.35%** — instrument change, [§4](#4-stage-f--the-coverage-number-moved-and-why-that-is-not-a-regression) |
| 2 | Suite green on the default Gemfile | ✅ exit 0, checked after every stage |
| 3 | Suite green on `Gemfile.next`, no longer allow-failure | ❌ **not met.** `continue-on-error` was removed anyway — a deliberate call, [§5](#5-what-still-blocks-rails-5-and-who-owns-it) |
| 4 | Zero `factory_girl` references | ✅ in all code and both lockfiles. Planning docs still carry the name; they are historical records and rewriting them would falsify the record |
| 5 | Zero positional controller-test calls | ✅ 89 live + 2 in comments converted, 9 files |
| 6 | No `mocha/setup`, `mocha/mini_test`, `minitest/unit` requires | ✅ — but not the way the plan specified, [§3.2](#32-criterion-6-as-written-was-unimplementable) |
| 7 | `rails-controller-testing` declared; 19 + 11 sites pass | ✅ present in the 5.0 lock only, absent from the 4.2 lock. 19 `assert_template` / 11 `assigns` confirmed |
| 8 | No `Devise::TestHelpers` | ✅ |
| 9 | No `serve_static_assets` | ✅ deleted, not renamed |
| 10 | Branch coverage enabled and reported | ✅ 70.79%, printed by `coverage:check`, not gated |
| 11 | Cucumber pass rate ≥ Phase 0 baseline | ✅ 154/154 on 4.2 |
| 12 | No `NextRails` branch in test code | ✅ the two version-conditional branches are both in the `Gemfile` |

**11 of 12.** Criterion 3 is the exception and was never reachable by harness work
alone — the plan said as much in [1.4](phase-2-implementation-plan.md), and [§5](#5-what-still-blocks-rails-5-and-who-owns-it)
gives the residue by name.

---

## 3. Where the plan was wrong

Six corrections. The first is the plan's own count; the rest are things no one had
measured.

### 3.1 The static-attribute count

`factories.rb` has **37** static attributes, not 35. With `attachable_factories.rb`'s
15 — which the plan got right — the conversion was **52 sites, not 50**.

### 3.2 Criterion 6 as written was unimplementable

The plan said to drop `require 'minitest/unit'` from three files. Doing so turned the
whole 4.2 suite into a load error, because that file is the **only** definition of the
legacy `MiniTest = Minitest` alias — and mocha 1.x's minitest adapter assigns
`::MiniTest::Assertion` (`mocha/integration/mini_test/adapter.rb:26`).

Three separate dependents fell out of this:

| Site | Was | Now |
|---|---|---|
| `test/support/mini_test_matchers.rb` | `module MiniTest::Assertions` | `Minitest::Assertions` |
| `test/minitest_helper.rb`, `spec/minitest_helper.rb` | `MiniTest::Reporters.use!` | `Minitest::Reporters` — the gem never defined the camelCase name; it only resolved through the alias |
| `test/test_helper.rb`, `spec/minitest_helper.rb` | — | `MiniTest = Minitest unless defined?(MiniTest)`, aliasing the one constant mocha needs instead of restoring a deprecated file |

Criterion 6 passes. Mocha stays on 1.x per [D4](phase-2-implementation-plan.md#d4--mocha-1x-vs-2x); the alias
is deletable the day mocha goes to 2.x.

### 3.3 Two tests had never run

`test/unit/extensions/active_record/base_test.rb:13` declared
`class TestExtensions < MiniTest::Unit`. `Minitest::Unit` is **not a TestCase** — it is
the deprecated shim class, so minitest never collected it and its two tests have not
executed in years. The name the author wanted, `MiniTest::Unit::TestCase`, is
`Minitest::Test` on minitest 5.

Renamed. Both tests now run and both pass, on 4.2 and on 5.0. This is why the test
count is 996 and not 994, and it accounts for the 75.82% → 75.87% move seen before
the simplecov bump.

### 3.4 factory_bot 5 changed the association *strategy*, not just the syntax

The plan's risk register anticipated "a factory's value silently changed". The actual
break was louder and bigger: **factory_bot 5.0 flipped `use_parent_strategy` to
`true`**. factory_girl 4.7 always ran `association` with `:create` regardless of the
parent's strategy; factory_bot 5 inherits it, so `build(:page)` started *building* an
unsaved `Section`, which `SectionNode#section=` hands to ancestry's `parent=`, which
raises `No child ancestry for new record`.

**21 unit errors, on both bundles.** Fixed with `FactoryBot.use_parent_strategy = false`
at the top of `test/factories/factories.rb`. This phase is a port; changing association
strategy would be a behaviour change smuggled in under a rename.

### 3.5 `EngineControllerHacks` — the plan never knew it existed

`test/support/engine_controller_hacks.rb` overrides `get`/`post`/`put`/`delete` on
`ActionController::TestCase` with **positional** signatures and calls `process` with
five positional arguments. Stage C's shim therefore never fired: it saw three args,
correctly declined to translate, and `params:` arrived at the controller as a literal
key. **21 failures and 27 errors** on the first stage-C run.

The module now takes kwargs and forwards them to `super`, leaving exactly one place —
the shim — that knows about the 4.2/5.0 calling-convention difference.

### 3.6 Rails 5.0 removed `Kernel#silence_stream`

`features/support/env.rb:85` called it, so on the 5.0 bundle cucumber raised
`NoMethodError` **at load** and the entire run died before collecting a scenario. This
is harness work and squarely in scope; it is also the single change that took 5.0
cucumber from "does not load" to "154 scenarios collected".

4.2 has it as `Kernel#silence_stream`; 5.0 keeps the implementation only as a private
method on `ActiveSupport::Testing::Stream`, a module that does not exist on 4.2. No
name resolves on both, so the six-line implementation is now defined locally as
`without_output_from` and neither version matters.

---

## 4. Stage F — the coverage number moved, and why that is not a regression

Measured across the simplecov 0.12 → 0.22 bump on **identical code**:

| | simplecov 0.12 | simplecov 0.22 |
|---|---|---|
| Covered lines | **4901** | **4901** |
| Relevant lines | 6460 | **6255** |
| Line coverage | 75.87% | **78.35%** |

The numerator is **identical**. Only the denominator moved — 0.18+ narrowed what counts
as a relevant line, so 205 lines left the measurement. That is the instrument changing,
exactly as [1.5](phase-2-implementation-plan.md) predicted, and it is the one reading
under which criterion 1 stays interpretable.

`COVERAGE_MINIMUM`'s default is now **78.35**. The gate itself was taught both JSON
shapes *before* the bump (`result['line'] || result['covered_percent']`), so it was
never broken across the transition, and it aborts on neither key rather than comparing
`nil` to a Float.

### A measurement hazard worth knowing about

`coverage/.resultset.json` is shared across bundles and suites, and entries persist for
`merge_timeout` (3600s). During this phase it accumulated an `Unknown Test Framework`
entry from a single-file Rails 5 run plus stale suites from earlier phases — any of
which silently shifts the merged percentage. **Clear the resultset before taking a
coverage measurement you intend to quote.** Every figure in this report was taken on a
cleared resultset with exactly the five expected suites present.

---

## 5. What still blocks Rails 5, and who owns it

Five application defects. None is harness work; all belong to
[Phase 3](phase-3-backwards-compatible-fixes.md).

| Defect | Impact |
|---|---|
| `skip_callback :redirect_to_cms_site` not defined — [`content_controller.rb:11`](../../app/controllers/cms/content_controller.rb#L11) | **Worst of the five.** 5.0 raises where 4.2 warned, and it is a *load* error: it takes the entire functional suite down and causes most of the 148 cucumber failures |
| `ActiveRecord::StaleObjectError` on `Cms::Page` ×2 | 2 unit errors |
| `PublishableTestCase#test_publish_on_save` | expected false to be truthy |
| `PortletTest#test_.blacklist` | expectation diff |
| `couldn't find file 'ckeditor-jquery'` | asset-pipeline resolution under 5.0; 132 of the cucumber failures |

### The `next-rails` CI job is now gating and currently red

This was a deliberate decision, taken with the residue above already known and
documented. The argument for it: a red job in the merge path is visible, and a
"reporting only" job that is red for four phases is how a genuine regression gets
missed. The cost: **CI is red on every PR until Phase 3 lands.** The job's comment
block names all five defects so the red is legible rather than mysterious.

> **Update after Phase 3.** All five were cleared and the job stayed red on ten
> different failures, so the "until Phase 3" estimate above was wrong — though the
> gating decision itself was re-made and kept. Turning the job green is now
> [Phase 4](phase-4-characterization-tests.md)'s work item 4.0. See
> [`phase-3-report.md` §6](phase-3-report.md).

### Newly found, deferred: `use_route`

`EngineControllerHacks` injects `:use_route => :cms` into every functional request.
4.2 deprecates it; **5.0 removed it**, so on the next bundle it is no longer consumed
and arrives at the controller as an ordinary request parameter.

The replacement 4.2's own deprecation message recommends — `@routes = Cms::Engine.routes` —
**is not equivalent, and this was measured, not assumed**: it produced **16
`UrlGenerationError`s**, because `use_route` is a route *name* hint into the
application's route set (`@routes.path_for(options, route_name)`), not a route-set
swap. The dummy app's own controllers (`dummy/sample_blocks`) are not in the engine's
route set at all.

Untangling which test classes want engine routes and which want application routes is
a real piece of work and is **not** the harness migration. 4.2 behaviour is preserved
exactly; the finding is recorded in the module's own comment so the next person does
not repeat the 16-error experiment.

### Also newly found: a dual-boot database hazard

Switching bundles leaves the test database in a state the other bundle rejects. After a
4.2 run, `bundle exec rake` on `Gemfile.next` aborts at `db:drop` with
`ActiveRecord::NoEnvironmentInSchemaError` — Rails 5's protected-environment guard
looking for `ar_internal_metadata`. Clear it with
`BUNDLE_GEMFILE=Gemfile.next bundle exec rake app:db:environment:set`. CI does not hit
this because each job gets a fresh container, but every local dual-boot run does.

---

## 6. What changed

| Stage | Change |
|---|---|
| **A** | `create_or_update(*args, &block)`; `Rails::Html::FullSanitizer` ×2. Two Phase 3 fixes borrowed per [D1](phase-2-implementation-plan.md#d1--borrowing-two-fixes-from-phase-3) — they took 5.0 unit errors from 323 to 3 |
| **B** | `factory_bot_rails ~> 5.2`, `mocha ~> 1.16`; 14 files renamed; 52 static attributes converted; `use_parent_strategy = false`; the `MiniTest` alias and its three dependents |
| **C** | `KeywordControllerArgs` shim (4.2 only); 89 call sites + 2 comments; `EngineControllerHacks` made kwargs-aware; `rails-controller-testing` behind `next?`; `Devise::Test::ControllerHelpers`; the dead `Cms::IntegrationTestHelper` call converted and flagged |
| **D** | Static-asset config keys deleted from `test.rb` and `production.rb` — nothing set them false, both frameworks default them true |
| **E** | `poltergeist` gone from the Gemfile and `env.rb`; `silence_stream` replaced |
| **F** | `simplecov ~> 0.22.0`, `enable_coverage :branch`, gate taught both JSON shapes, baseline moved to 78.35 |
| **G** | `next-rails` made gating; this report |

### Lockfile drift, both files, fully accounted for

`factory_girl` → `factory_bot` (with its dependency bounds); `mocha` 1.2 → 1.16 and
`metaclass` dropped; `simplecov` 0.12 → 0.22 with `docile` and `simplecov-html` bumped,
`simplecov_json_formatter` added and the `json` gem dropped (a 0.12 dependency);
`poltergeist` dropped with `cliver`, `websocket-driver` and `websocket-extensions`;
`rails-controller-testing` added to the **next lock only**. Nothing else moved.

---

## 7. For Phase 3

1. The five defects in [§5](#5-what-still-blocks-rails-5-and-who-owns-it). Do the
   `skip_callback` one first — it is a load error, so nothing downstream of it is
   measurable until it lands.
2. `use_route` in `test/support/engine_controller_hacks.rb`.
3. Set a branch-coverage floor now that 70.79% is a measured number.
4. Dead code: `Cms::IntegrationTestHelper` is defined, included nowhere, and asserts
   `403` immediately after a successful login.
5. The `MiniTest = Minitest` alias goes when mocha goes to 2.x.
