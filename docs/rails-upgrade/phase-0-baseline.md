# Phase 0 — Recorded Baseline

> Exit criteria 4, 6 and 7 of [`phase-0-baseline-and-ci.md`](phase-0-baseline-and-ci.md).
> Measurements, not intentions. The reasoning behind them is in [`phase-0-implementation-plan.md`](phase-0-implementation-plan.md).

**Date:** 2026-07-28 · **Branch:** `feature/cms-420-migrate-tests`
**Ruby:** 2.7.8 · **Rails:** 4.2.11.3 · **Postgres:** 16 (local), 15 (CI)
**Command:** `RAILS_ENV=test bundle exec rake`, plus `rake features:all` and `rake features:cli`

`RAILS_ENV=test` is not optional — see [Environment findings](#environment-findings).

---

## Headline

| | |
|---|---|
| Minitest | **994 tests, 0 failures, 0 errors, 19 skips** |
| Cucumber, non-`@cli` (default `rake` subset) | **154 / 154 scenarios pass** |
| Cucumber, non-`@cli`, all tags | **154 / 159 pass** — 2 fail (`@known-bug`), 3 pending (`@missing-feature`) |
| Cucumber, `@cli` | **7 / 34 scenarios pass (20.6%)** |
| Coverage | **75.82%** (4,898 / 6,460 relevant lines) |

**The `@cli` number is this phase's most important output.** The generator and
command-line features — the only coverage `lib/generators` has — are 79% red.

## Minitest suites

| Suite | Tests | Assertions | Failures | Errors | Skips | Time |
|---|---|---|---|---|---|---|
| Unit (`test/unit`) | 754 | 1,749 | 0 | 0 | 3 | 47s |
| Spec (`spec`) | 145 | 260 | 0 | 0 | 7 | 20s |
| Functional (`test/functional`) | 88 | 203 | 0 | 0 | 9 | 10s |
| Orphans (`test:orphans`, new) | 7 | 9 | 0 | 0 | 0 | 0.1s |
| **Total** | **994** | **2,221** | **0** | **0** | **19** | |

The orphan suite runs 9 files but only 7 tests: `catalogs_controller_test.rb`
and `content_page_helper_test.rb` are empty generator scaffolds with no test
methods. They are in the chain and green; they assert nothing.

## Cucumber

| Profile | Scenarios | Passed | Failed | Pending | Steps |
|---|---|---|---|---|---|
| `features` — default subset (`~@cli ~@known-bug ~@missing-feature`) | 154 | 154 | 0 | 0 | 837 |
| non-`@cli`, **all** tags | 159 | 154 | 2 | 3 | 864 |
| `features:cli` — the 9 `@cli` files | 34 | 7 | 27 | 0 | 161 |

**Pass rate across all 53 feature files: 161 / 193 scenarios = 83.4%.**
Excluding `@cli`, it is 154 / 159 = 96.9%.

### The 5 tag-excluded non-`@cli` scenarios

Six scenarios carry `@known-bug` or `@missing-feature`; one of them
(`generate_module.feature:10`) is also `@cli` and is counted in that set
instead. The remaining five are what separates 154 from 159:

| Scenario | Tag | Outcome |
|---|---|---|
| `features/portlets/portlets.feature:94` — Portlet errors should not blow up the page | `@known-bug` | **fails** |
| `features/content_pages.feature:25` — View Older Versions | `@missing-feature` | **fails** |
| `features/cucumber.feature:11` — Upgrade Cucumber | `@known-bug` | pending |
| `features/page_templates.feature:20` — Multiple pages of templates | `@known-bug` | pending |
| `features/page_templates.feature:29` — Edit a template | `@known-bug` | pending |

### Reconciliation

A bare `cucumber features` run — every file, every tag — reports
**193 scenarios: 161 passed, 29 failed, 3 pending**. That decomposes exactly:

```
154 pass  default profile          + 7 pass  @cli   = 161 passed
 27 fail  @cli                     + 2 fail  tagged =  29 failed
  3 pending (all @known-bug)                        =   3 pending
154 + 5 + 34                                        = 193 scenarios
```

Nothing in that run is unaccounted for, and nothing in it is a regression.

### The 27 `@cli` failures — one dominant root cause
`rails new petstore --skip-bundle` does not exit cleanly inside aruba. The
cached project it should produce is never created, and **15 of the 27 failures
are downstream `Errno::ENOENT` on that missing directory**. Fixing the root
command plausibly recovers most of the suite; it was not attempted in Phase 0,
which is a measurement phase. Tracked as [O1](#open-items).

Before this could be measured at all, a `Cucumber::Ambiguous` abort had to be
removed — see [Changes made](#changes-made).

## Coverage

| Configuration | % | Covered | Relevant |
|---|---|---|---|
| Raw, no filters — reproduces `TEST_COVERAGE_PLAN.md` exactly | 72.64 | 4,898 | 6,743 |
| Generator templates filtered (`.simplecov`) | **75.82** | 4,898 | 6,460 |

**Enforced floor: 75.82%**, checked by `rake coverage:check`, which `ci:test`
runs after the suite. Override with `COVERAGE_MINIMUM`.

`lib/generators` (5 files, 198 counted lines, 0%) is **kept in the denominator**
— see [D2](#decisions).

## Environment findings

| Question | Answer |
|---|---|
| Does `bundle exec rake` work without `RAILS_ENV=test`? | **No.** `db:install` → `db:migrate` boots the dummy app in `development`, and `test/dummy/config/database.yml` defines only `test`. Aborts with `ActiveRecord::AdapterNotSpecified`. Travis's `script: bundle exec rake` could not have passed. |
| Is PhantomJS installed? | No — and the suite is green anyway. |
| Does any scenario select the Poltergeist driver? | **No.** Zero `@javascript` tags in `features/`; both driver assignments at `features/support/env.rb:16-17` are commented out. `require 'capybara/poltergeist'` loads the gem and nothing ever uses it. **CI needs no PhantomJS.** |
| Suites in `coverage/.resultset.json` | Unit Tests, RSpec, Functional Tests, Orphan Tests, Cucumber Features — five distinct names, none overwriting another. |
| Does `rake app:test` run the dummy app's tests? | **No.** It exits 0 having run nothing. |

## Quarantine register

19 skips. Every one already carried a reason string before Phase 0; none has a
linked issue. No test was newly quarantined by this phase.

| Test | Reason as written |
|---|---|
| `test/unit/models/file_block_test.rb:48` | RuntimeError: unsupported: TrueClass |
| `test/unit/behaviors/attaching_test.rb:451,458` | `changed?` is not updating with rails 4 |
| `test/functional/cms/file_blocks_controller_test.rb:13` | deeper dive needed on why these indexes are not rendering |
| `test/functional/cms/html_blocks_controller_test.rb:39` | deeper dive needed on why these indexes are not rendering |
| `test/functional/cms/pages_controller_test.rb:135` | Work out how page creation has changed |
| `test/functional/cms/home_controller_test.rb:59` | Page routing is not working correctly |
| `test/functional/cms/content_controller_test.rb:22,63,70` | Page routing / routes not working as expected |
| `test/functional/cms/content_controller_test.rb:41` | Archived pages are not visible, but maybe should be for admins |
| `test/functional/cms/sections_controller_test.rb:158` | Admin related operations are failing |
| `spec/cms/form_spec.rb:14,33` · `spec/inputs/name_input_spec.rb:13,19,25` | Form addressability removed 6 years ago (`app/models/cms/form.rb:5`) |
| `spec/cms/form_spec.rb:22` | Parent not getting created (in rails 4?) |
| `spec/concerns/addressable_spec.rb:71` | Parent relationships broken in bcms4 |

Two clusters are worth noting: **five skips blame page routing** in the
functional controller tests, and **six blame removed/broken addressability**.
Neither is a Phase 0 problem, but both are concentrated enough to be one bug
each rather than eleven.

## Changes made

| Change | Why |
|---|---|
| `.simplecov`: `merge_timeout 3600` | Default 600s silently drops the earliest suites from a full run's merged report. Observed producing a 0.0% report. |
| `.simplecov`: `command_name` per suite; `Rakefile` sets `COVERAGE_SUITE` | SimpleCov guesses suite names, and two suites that guess alike overwrite each other. |
| `.simplecov`: template filters as **blocks** | 0.12 raises `ArgumentError` on a `Regexp` filter, and `defaults.rb` rescues it — a regex filter abandons the rest of `.simplecov` with one stderr line. Both the plan's and `TEST_COVERAGE_PLAN.md` §0a's suggested snippets were wrong here. |
| `Rakefile`: new `test:orphans` task, added to the `:test` chain | 10 test files were outside every pattern. `rake app:test` is a silent no-op, so it could not be used. |
| `test/dummy/test/unit/portlets/{find_category,uses_helper}_portlet_test.rb` | Both required `../../test_helper`, which resolves to a `test/dummy/test/test_helper.rb` that does not exist. |
| `test/dummy/test/controllers/design_controller_test.rb` | `get :show` passed no `:page` param, so the action rendered nil and fell through to a `design/show` template that has never existed. |
| Deleted `test/helpers/cms/content_types_helper_test.rb` | A single `flunk "Need real tests"` that referenced `ContentTypesHelper` — not a real constant (the helper is `Cms::ContentTypesHelper`). It could not even load. |
| Merged `test/unit/lib/cms_domain_support_test.rb` into `.../cms/domain_support_test.rb` | Not duplicates: one tested `cms_site?`/`cms_domain_prefix`, the other `using_cms_subdomains?`. All real cases kept; one empty stub dropped. |
| Deleted the redundant `the file "..." should not contain:` step | Collided with aruba 0.14's own, aborting the entire `@cli` run with `Cucumber::Ambiguous` before any result was reported. |
| Removed `$VERBOSE = nil` from `test/test_helper.rb` | It silenced the Ruby-level deprecation warnings that are the upgrade roadmap. |
| `File.exists?` → `File.exist?`, 7 call sites | Deprecated. One of them was stubbed by `attaching_test.rb:247`, which had to move with it. |
| `Rakefile`: `ci:test` now runs `coverage:check` | Enforces the floor once, after the chain. |
| `.github/workflows/ci.yml` | There was no CI. |
| `test/dummy/db/schema.rb` regenerated | See [O2](#open-items). |

## Deprecation inventory

Visible in the CI log now that warnings are on. This is the Phase 3 work list,
recorded here because Phase 0 is where it became visible.

| Count | Warning | Where |
|---|---|---|
| 44 | `#timestamps` called without `null:` — changes in Rails 5 | migrations |
| 29 | `#add_timestamps` called without `null:` | migrations |
| 24 | passing an AR instance to `find` | `app/models/cms/category.rb:33` |
| 8 | `#deliver` removed in Rails 5 | mailers |
| many | `use_route` in functional tests — **removed in Rails 5, no replacement** | `test/support/engine_controller_hacks.rb:33` |
| 2 | `config.serve_static_assets` renamed | `test/dummy/config/environments/test.rb:11` |
| 1 | `Devise::TestHelpers` → `Devise::Test::ControllerHelpers` | `test/test_helper.rb:199` |
| 1 | `active_support.test_order` default changes to `:random` | unset |
| 97 | Ruby: `Object#=~` called on `Cms::ContentType` | see below |
| 69 / 52 / 45 | Ruby: `Proc.new` block capture, `Fixnum`, `Bignum` | gem internals (activerecord, simplecov, simple_form) |

### One of those is a latent defect, not just noise

`Cms::ContentBlockController#content_type` (`app/controllers/cms/content_block_controller.rb:152`)
overrides `ActionController::Metal#content_type`, returning a `Cms::ContentType`
record instead of the response MIME string. Rails' CSRF protection then runs
`content_type =~ %r(\Atext/javascript)` at
`request_forgery_protection.rb:242`, which on a non-String is `Object#=~` and
**always returns nil** — so `non_xhr_javascript_response?` is permanently false
for every content-block controller, and that cross-origin JavaScript check
never fires. Renaming a public helper method is out of Phase 0's scope; tracked
as [O3](#open-items).

## Decisions

| ID | Decision | Outcome |
|---|---|---|
| **D1** | How to handle the `RAILS_ENV` requirement | **Set `RAILS_ENV: test` in CI**, leave `database.yml` alone. Phase 0 must measure the suite as it is. Adding a `development:` section is the better long-term fix — [O4](#open-items). |
| **D2** | Exclude `lib/generators` from coverage? | **No — keep it in the denominator.** The standing recommendation was to exclude it because the `@cli` features cover it out of process. Phase 0 measured those features: 7 of 34 pass. The 0% is a measurement gap sitting on a real testing gap, and excluding it would misreport the second one. Revisit once [O1](#open-items) is fixed. |
| **D3** | `test/assumptions_test.rb` | **Kept.** It was predicted to fail once wired in, because `db:install` seeds a Home page and a `/system` section. It passes: `app:test:prepare` purges and reloads the schema before any test runs, so the seed data is gone by then. The prediction was wrong; the test is valid. |
| **D4** | The `flunk` stub test | **Deleted.** It never asserted anything and referenced a constant that does not exist. |
| **D5** | The two empty scaffold test files | **Kept**, now inside the chain. Recorded here so nine files are not mistaken for nine tests. |

## Open items

Not Phase 0 work. Recorded so a reviewer can tell a gap from an oversight.

| ID | Item |
|---|---|
| **O1** | `@cli` features are 7/34. One root cause — `rails new` failing inside aruba — accounts for 15 of the 27 failures. Fix it and re-measure before revisiting [D2](#decisions). |
| **O2** | `test/dummy/db/schema.rb` as committed contained 27 tables that no migration creates — ephemeral fixtures (`default_attachables`, `publishable_blocks`, `things`, …) that tests build at runtime and a `db:schema:dump` then captured. The committed file is now what a clean migrate produces, but any partial test task can re-dirty it. Consider gitignoring it: CI builds the database from migrations. |
| **O3** | The `content_type` override disabling CSRF's cross-origin JavaScript check (above). |
| **O4** | `bundle exec rake` is broken without `RAILS_ENV=test` for every developer, not just CI. |
| **O5** | Five skips blame page routing; six blame removed addressability. Likely two bugs, not eleven. |
| **O6** | The 19 skips have reasons but no linked issues. |
