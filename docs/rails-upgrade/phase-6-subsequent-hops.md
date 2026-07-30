# Phase 6 — Subsequent Hops (5.1 → 8.0)

> ## Goal
> **Repeat a known-good loop for each remaining version, one minor at a time, ending with Rails 8.x green and deployed.**
>
> This file is a template, not a plan. It is deliberately thinner than Phases 0–5 because **only the 4.2 → 5.0 hop has had a real detection pass.** Anything more specific about 6.x/7.x/8.x would be invented rather than measured.

**Rails version at the end:** 8.x.
**Remaining hops:** 5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0. **Nine versions, no skipping.**

---

## Why this file is a template

The supporting analysis was reconciled against the `rails-upgrade` skill **for the 4.2 → 5.0 hop only**. Its Tier C table lists removal versions for later hops, and those versions are now skill-sourced and trustworthy — but **a version claim is not a detection pass.** Nobody has run the 6.0, 7.0, or 8.0 pattern sets against this codebase.

Writing detailed phase files for those hops now would produce confident-looking documents with nothing behind them. The honest move is to record the loop, flag the three hops that are known to be hard, and re-run detection when each one arrives.

## The per-hop loop

Run this for every hop. It is Phases 0–5 compressed, because the expensive one-time work (CI, harness, dual-boot) is already done.

| Step | Action | Skill reference |
|---|---|---|
| 1 | **Confirm you're on the latest patch** of the current series before moving | `SKILL.md` Step 0 — applies at *every* hop, not just the first |
| 2 | **Confirm the suite is green** on the current version | `workflows/test-suite-verification-workflow.md` |
| 3 | **Repoint `Gemfile.next`** at the next version | the `dual-boot` skill |
| 4 | **Run the detection patterns** for the target version | `detection-scripts/patterns/rails-{VERSION}-patterns.yml` |
| 5 | **Read the hop guide** | `version-guides/upgrade-{FROM}-to-{TO}.md` |
| 6 | **Check gem compatibility** against the target | `workflows/gem-compatibility-workflow.md` |
| 7 | **Boot smoke test** against `Gemfile.next` | `workflows/boot-smoke-test-workflow.md` |
| 8 | **Fix `kind: breaking` and `kind: deprecation` findings** *before* the bump | `SKILL.md` Step 6 |
| 9 | **Bump**, run both suites, sync CI | `workflows/ci-sync-workflow.md` |
| 10 | **Align `load_defaults`** as a separate change — but see the engine caveat below | the `rails-load-defaults` skill |
| 11 | **Capture forward-looking deprecations; do not fix them** | carry to the next hop |
| 12 | **Deploy before starting the next hop** | — |

### Two rules that apply at every hop

**Prefer backwards-compatible fixes.** Most replacements work on both versions, which means they can ship independently of the bump — the [Phase 3](phase-3-backwards-compatible-fixes.md) pattern. Use `NextRails.next?` only when the fix genuinely requires an API that doesn't exist in the current version. Never `respond_to?`.

**`load_defaults` is a support-range question, not a config change.** BrowserCMS is an engine; the host app owns the flag. Every hop that introduces a `load_defaults`-gated behaviour change means re-answering "which host values do we support?" See [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.3](../../RAILS_UPGRADE_TEST_PRIORITY.md).

---

## The hops that are known to be hard

Difficulty ratings are the skill's. Three of the nine carry most of the risk.

| Hop | Difficulty | What lands | Already prepared? |
|---|---|---|---|
| 5.0 → 5.1 | ⭐ Easy | `*_filter` removed, `render text:` removed, `Relation#uniq` removed, `redirect_to :back` removed | ✅ **Mostly done** on the code side. All three removals fixed in [Phase 3](phase-3-backwards-compatible-fixes.md); `redirect_to :back` verified absent. ⚠️ **But two gems block this hop**, measured in [Phase 1](phase-1-gem-report.md): `cucumber-rails 1.4.5` caps `railties < 5.1` (it clears 5.0, so the cucumber-stack work can be deferred to exactly here), and `minitest` is pinned down to `~> 5.10.3` to work around Rails 5.0's test reporter — revisit at 5.1. |
| 5.1 → 5.2 | ⭐⭐ Medium | Bare `HashWithIndifferentAccess`; unquoted `class_name:` constants now raise `ArgumentError`; `halt_callback_chains_on_return_false` config removed | ✅ Partly. `HashWithIndifferentAccess` qualified in Phase 3. The config and unquoted `class_name:` are **verified absent in browsercms** — but `cms` has **11 unquoted `class_name:` sites**, which become a hard boot failure here. |
| 5.2 → **6.0** | ⭐⭐⭐ **Hard** | **Zeitwerk**, `update_attributes` removed, Action Mailbox/Text, Ruby 2.5+ | ⚠️ **Partly.** `update_attributes` done in Phase 3; [Phase 4](phase-4-characterization-tests.md)'s eager-load test is the Zeitwerk defence. **The rest is a phase of its own — see below.** |
| 6.0 → 6.1 | ⭐⭐ Medium | Horizontal sharding, strict loading, `ActiveModel::Errors` **rewritten** | ⚠️ `lib/cms/extensions/active_record/errors.rb` patches `ActiveModel::Errors` and is **untested**. Write its characterization test before this hop. |
| 6.1 → **7.0** | ⭐⭐⭐ **Hard** | Hotwire/Turbo, Import Maps, `rails-ujs` removed, classic autoloader **removed outright** | ❌ Not prepared. `jquery_ujs` at `application.js:5` and `page_editor.js:2`; `jquery-rails` pinned at 3.1. |
| 7.0 → 7.1 | ⭐⭐ Medium | Composite keys, async queries | ❌ Not assessed |
| 7.1 → **7.2** | ⭐⭐ Medium | Transaction-aware jobs, `show_exceptions` symbols, **Ruby 3.1+ required** | ⚠️ **Ruby 2.7.8 carries through 7.1 and stops here.** Plan the Ruby upgrade into this hop. |
| 7.2 → **8.0** | ⭐⭐⭐⭐ **Very Hard** | **Propshaft**, Solid gems, Kamal, multi-database config | ❌ Not prepared. Sprockets 3 + **EOL Compass**; `app/assets/stylesheets/cms/*.scss` needs a new pipeline. Not unit-testable — this hop depends on the Cucumber suite being healthy. |

### The 6.0 Zeitwerk hop needs its own phase file

It is the largest single item in the whole upgrade, and unlike everything else it cannot be reduced to a checklist in advance. `lib/cms/engine.rb` is 135 lines with a **7-line test containing 1 assertion**, and it:

- pushes 6 directories onto `ActiveSupport::Dependencies.autoload_paths` — an API Zeitwerk does not have
- anchors an initializer `:after => 'action_controller.deprecated_routes'`, an initializer **that no longer exists**
- calls `routes_reloader.reload!` in `after_initialize`

And the loaders around it are the classic Zeitwerk failure pattern: `lib/cms/behaviors.rb:32` and `lib/cms/concerns.rb:6` build class names from filenames with `File.basename(b, ".rb").camelize` and `constantize` them at load time, while `lib/browsercms.rb:36-67` does `ActiveRecord::Base.send(:include, ...)` at require time. Zeitwerk forbids this shape.

**When you reach 5.2, write `phase-7-zeitwerk.md` before starting the hop.** Its inputs: [Phase 4](phase-4-characterization-tests.md)'s eager-load test output, a fresh `rails-60-patterns.yml` detection pass, and engine/autoload contract tests documenting which paths land where. See [`TEST_COVERAGE_ANALYSIS.md` §3.6](../../TEST_COVERAGE_ANALYSIS.md) and Phase 2d of its plan.

---

## Exit criteria

### Per hop

| # | Criterion | How to verify |
|---|---|---|
| 1 | On the **latest patch** of the target series | `bundle list \| grep " rails "` against RubyGems |
| 2 | Full suite green — unit, spec, functional, features | CI passing |
| 3 | Coverage at or above the previous hop's number | Coverage artifact comparison |
| 4 | **Cucumber pass rate at or above Phase 0's baseline** | Compare against the committed number — this is the metric most likely to erode silently across nine hops |
| 5 | A detection pass was **actually run** for this version, and its findings are committed | The pattern-run output is in the repo. Reading the version guide is not a detection pass. |
| 6 | Gem compatibility check run; blockers have written decisions | Committed three-bucket report for this hop |
| 7 | CI config matches the Gemfile — no DRIFT | ci-sync verdict OK |
| 8 | `load_defaults` support range re-answered if this hop changed it | Statement updated or explicitly confirmed unchanged |
| 9 | Forward-looking deprecations captured, not fixed | Committed list carried forward |
| 10 | Deployed and stable before the next hop begins | — |

### Overall

| # | Criterion | How to verify |
|---|---|---|
| A | Rails **8.x** in `Gemfile.lock`, gemspec constraint updated | `bundle list \| grep " rails "` |
| B | All nine hops shipped **sequentially**, each deployed before the next | Git history shows nine distinct bumps, none skipping a version |
| C | Coverage ≥ the Phase 0 baseline, with branch coverage reported | Coverage artifact |
| D | Cucumber suite ≥ Phase 0's pass rate | Committed comparison |
| E | Ruby ≥ 3.2 (8.0's floor) | `cat .ruby-version` |
| F | Paperclip, Sprockets/Compass, Devise config, SimpleForm, `jquery-rails`, and the vendored `acts_as_list` fork all resolved | Each has a shipped decision — replaced, upgraded, or removed |
| G | Dual-boot scaffolding retired | `NextRails` absent from `app/`, `lib/`, `test/`, `spec/`; no `Gemfile.next`. Run the `upgrade-cleanup` plugin — **only when explicitly asked.** |
| H | No `require_dependency`, no `ActiveSupport::Dependencies.autoload_paths` | `grep -rn "require_dependency\|autoload_paths" app/ lib/` returns nothing |

**Done means:** criterion B holds — nine sequential, individually-deployed hops — with C and D showing the test net never shrank along the way.

---

## Explicitly not in this file

- **Detailed work items for 6.x, 7.x, or 8.x.** They'd be fiction. Run the detection patterns when you get there.
- **Effort estimates.** Nine hops of unmeasured work; any number would be invented.
- **The Zeitwerk plan.** Genuinely needs its own file, written at 5.2 when the eager-load test has told you what you're dealing with.
- **The `cms`-side work.** Its blockers — the 11 unquoted `class_name:` constants (fatal at **5.2**), `override_csrf_encode_decode.rb`'s `exit(1)` guard that hard-fails boot unless `Rails.version == '4.2.11'`, and `browsercms_overrides.rb` at 28.8% coverage — are real and some are urgent, but they belong to that repo's plan. See [`TEST_COVERAGE_ANALYSIS.md` §5](../../TEST_COVERAGE_ANALYSIS.md).
