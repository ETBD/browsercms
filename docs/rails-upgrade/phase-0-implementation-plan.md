# Phase 0 — Implementation Plan

**Implements:** [`phase-0-baseline-and-ci.md`](phase-0-baseline-and-ci.md)
**Rails version throughout:** 4.2.11.3 (unchanged)
**Branch:** continue on `feature/cms-420-migrate-tests`, or cut `feature/cms-420-phase-0` from it.

This is the *how*. The phase file states the goal and the contract; this file states the order of operations, the exact edits, the failures to expect, and the decisions that need a human. Where the two disagree, the divergence is called out explicitly in [§1](#1-pre-flight-findings) — the phase file was written from static reading, and several of its assumptions do not survive contact with the repo.

> ### Status: executed
> Measured results are in [`phase-0-baseline.md`](phase-0-baseline.md); that file, not this one, is the record. Where execution contradicted the plan:
>
> | Plan said | Reality |
> |---|---|
> | F4: one file requires a missing `test_helper` | **Two** — `find_category_portlet_test.rb` and `uses_helper_portlet_test.rb`. |
> | F5: `assumptions_test.rb` will fail once wired in | **It passes.** `app:test:prepare` purges and reloads the schema before any test runs, so `db:install`'s seed data is gone by then. |
> | Stage G.1: filter with `add_filter %r{…}` | **SimpleCov 0.12 rejects Regexp filters entirely** — `parse_filter` raises `ArgumentError`, and `defaults.rb` rescues it around `load .simplecov`, so a regex filter silently abandons the rest of the config file. Use block filters. The plan's snippet and `TEST_COVERAGE_PLAN.md` §0a were both wrong, in different ways. |
> | Stage E: flip `t.warning = true` | **Not done.** Removing `$VERBOSE = nil` restores Ruby's default warning level, which is what surfaces the deprecations. `-w` additionally enables the uninitialized-ivar and method-redefined classes, almost all of it from gem internals. `RUBYOPT=-W:deprecated` in CI covers criterion 10 without the noise. |
> | Stage E: `File.exists?` fixes are mechanical | One of the seven call sites was **stubbed by a test** (`attaching_test.rb:247`), which broke two tests until the stub moved with it. |
> | Stage B: measure the `@cli` pass rate | Could not be measured at all until a `Cucumber::Ambiguous` step collision was removed — it aborted the run before the first result. |
>
> Also unplanned: running the suite rewrites `test/dummy/db/schema.rb`, because the committed version contained 27 ephemeral fixture tables no migration creates. See O2 in the baseline.

---

## 1. Pre-flight findings

Verified against the working tree at `b00c2c04` on 2026-07-28, before any work started. Each of these changes the plan.

| # | Finding | Evidence | Consequence |
|---|---|---|---|
| **F1** | **`bundle exec rake` — the documented default command, and Travis's `script` — fails immediately.** `ci:test` → `db:install` → `db:migrate` boots the dummy app in `development`, and `test/dummy/config/database.yml` defines **only** `test`. | `bundle exec rake db:migrate` → `ActiveRecord::AdapterNotSpecified: 'development' database is not configured. Available: ["test"]`. With `RAILS_ENV=test` it boots fine. | Every command in this phase is `RAILS_ENV=test bundle exec rake …`. Fixing it properly is a decision — see [D1](#d1-railsenv). It also means `.travis.yml` could not have been green; treat the Travis config as evidence of *intent*, not of a working build. |
| **F2** | **`rake app:test` is a silent no-op.** It exits 0 having run nothing. Rails 4.2's `test` task passes `Rake.application.top_level_tasks` (`["app:test"]`) to `Rails::TestTask.test_creator`, which matches no known sub-task. | `bundle exec rake app:test` → exit 0, zero output. | Phase file §0.2's "`rake app:test` would run them" is **false**. Do not wire `app:test` into the chain; a task that silently passes is worse than one that fails. Use a new `Rake::TestTask` instead ([Stage D](#stage-d--wire-in-the-orphaned-tests-02)). |
| **F3** | **`rake app:test:run` does run — but globs from the engine root, not the dummy app**, and dies on boot. Its pattern `test/**/*_test.rb` is relative to the cwd, so it sweeps up `test/unit`, `test/functional`, `test/assumptions_test.rb` and the dummy tests together. | `bundle exec rake app:test:run` → aborts inside `test/assumptions_test.rb:1` → `test_helper.rb:4` → `AdapterNotSpecified`. | Confirms F2's replacement approach, and confirms `test/assumptions_test.rb` is loadable (its `require "test_helper"` resolves) once `RAILS_ENV` is right. |
| **F4** | **There is no `test/dummy/test/test_helper.rb`.** `test/dummy/test/unit/portlets/find_category_portlet_test.rb:1` requires `../../test_helper`, which resolves to that missing path. The other seven use a bare `require "test_helper"`, which resolves to the engine's `test/test_helper.rb` **only if** `test/` is on the load path. | `ls test/dummy/test/*.rb` → no matches. | Wiring the 8 dummy tests needs `t.libs << 'test'` (engine `test/`) **and** a fix for the one relative require — either edit that line, or add a one-line `test/dummy/test/test_helper.rb` shim. Prefer editing the one file. |
| **F5** | **`test/assumptions_test.rb` will fail the moment it is wired in.** It asserts `Section.count == 0`, but `db:install` (inside `ci:test`) seeds a Home page and a `/system` section. | The test's own body, plus the comment block at `test/test_helper.rb:32-40` describing exactly that seeded state. | Expected red, same category as `content_types_helper_test.rb`. Decision [D3](#d3-assumptions_testrb). |
| **F6** | **The two domain-support tests are not duplicates.** `test/unit/lib/cms_domain_support_test.rb` covers `cms_site?` and `cms_domain_prefix` on `Cms::ApplicationController`; `test/unit/lib/cms/domain_support_test.rb` covers `using_cms_subdomains?` through the module. Ten distinct cases, one empty stub. | Both files read in full. | Phase file §0.2's "de-duplicate — overlapping tests of the same file" overstates it. **Merge, don't delete**: move the three real cases from the former into the latter, drop the empty `"prepare_for_rendererable"` stub, delete the now-empty file. |
| **F7** | **Poltergeist/PhantomJS may be a paper tiger.** There are **zero `@javascript` tags** in `features/`, and both driver assignments in `features/support/env.rb:16-17` are commented out. PhantomJS is not installed on this machine. | `grep -rn '@javascript' features/` → 0. `which phantomjs` → not found. `features/support/env.rb:16-17`. | `require 'capybara/poltergeist'` loads the gem but nothing ever selects the driver, so **CI needs no PhantomJS**. Confirm during [Stage B](#stage-b--the-baseline-run-01) and record it — this materially shrinks [Phase 2](phase-2-harness-migration.md), whose driver-migration scope is sized on the assumption that the features depend on it. |
| **F8** | **`rake features` excludes more than `@cli`.** It also drops `~@known-bug` (5 scenarios) and `~@missing-feature` (1). | `Rakefile:51`; `grep -rho '@known-bug\|@missing-feature' features/`. | Exit criterion 6 ("the Cucumber pass rate is known") needs three runs, not two: `features`, `features:cli`, and `features:all`. Otherwise the recorded denominator excludes 16 scenarios by construction. |
| **F9** | **SimpleCov's 600-second `merge_timeout` will silently corrupt the coverage number** on any full run. The four suites are separate processes that merge through `coverage/.resultset.json`; 0.12 discards stored results older than `merge_timeout` (default 600s). | Demonstrated accidentally today: a late single-suite run regenerated the report and the four baseline suites dropped out — `coverage/.last_run.json` read `0.0`. Restored to 72.64% by re-merging with a raised timeout. `simplecov-0.12.0/lib/simplecov/configuration.rb:206`. | **Must be fixed before the baseline run**, or the recorded number is fiction. This is why [Stage A](#stage-a--make-the-measurement-trustworthy-prerequisite-to-01) precedes work item 0.1. |
| **F10** | **`minimum_coverage` cannot be set naively.** SimpleCov enforces it in *every* process's `at_exit` and calls `Kernel.exit` — so the units suite would fail the build for not, by itself, meeting the full-suite threshold. | `simplecov-0.12.0/lib/simplecov/defaults.rb:52-95`. | Gate once, after the chain, from `coverage/.last_run.json` (written unconditionally, line 90). See [Stage G](#stage-g--make-coverage-honest-03). |
| **F11** | **SimpleCov names suites by guessing**, and the guesser is fragile — today's stray run was filed as `"Unknown Test Framework"`. Two suites that guess the same name overwrite each other in the resultset. | `coverage/.resultset.json` keys; `SimpleCov::CommandGuesser`. | The new orphan-tests `Rake::TestTask` added in Stage D is at real risk of being guessed as `"Unit Tests"` and **silently clobbering** the units coverage. Set `command_name` explicitly per suite and verify the resultset has five distinct keys. |
| **F12** | **`$VERBOSE = nil` suppresses Ruby warnings only — Rails deprecations are already visible.** `RAILS_ENV=test bundle exec rake db:migrate` prints `config.serve_static_assets` → `serve_static_files` (from `test/dummy/config/environments/test.rb:11`, a Rails 5.0 removal) and the `after_rollback`/`after_commit` warning today, with `$VERBOSE = nil` in force. | Observed output. | Phase file §0.5's framing ("suppresses Ruby *and Rails* deprecation warnings") is half right. Removing it surfaces the **Ruby** layer: `File.exists?` (5 call sites), uninitialized ivars, method redefinitions. Both layers matter; they need different switches (`-W:deprecated` vs. nothing). |

Two smaller notes carried into the steps below: `test/dummy/config/database.yml` **is** tracked (so CI needs no `project:setup`), and `rake` itself lives in the `:development` group (`Gemfile:20`), so Travis's `--without development` should not be carried over.

---

## 2. Execution order

The phase file numbers its work items 0.1 → 0.5. That is the right order to *read* them and the wrong order to *do* them, for two reasons: the measurement harness must be trustworthy before the baseline run is worth recording (F9), and CI should be stood up while the suite is still red, because the runner surfaces failures a Mac never will.

| Stage | Work item | What it produces | Size |
|---|---|---|---|
| **A** | 0.3 (partial) | `merge_timeout` fixed, per-suite `command_name` — the number can be trusted | S |
| **B** | 0.1 | The baseline run: four suites + all three cucumber profiles, logged | M |
| **C** | 0.4 (partial) | `.github/workflows/ci.yml` landed, allowed to be red | M |
| **D** | 0.2 | Ten orphan tests inside the chain; domain-support tests merged | M |
| **E** | 0.5 | `$VERBOSE = nil` gone, warning noise triaged | M–L |
| **F** | 0.1 (triage) | Zero failing tests; every quarantine annotated | **L / unknown** |
| **G** | 0.3 (rest) | Honest denominator, `minimum_coverage` enforced once | S |
| **H** | 0.4 (rest) | CI green, coverage artifact, `.travis.yml` deleted | S |

**Stage F is the only unbounded one.** Its size is exactly what Stage B measures, which is why B comes early and why no estimate is offered here. If B reports a large share of the Cucumber suite red, stop and re-scope before continuing — that is the finding the README says the whole plan's shape depends on.

Stages D and E can run in parallel with C. Everything else is sequential.

---

## Stage A — Make the measurement trustworthy (prerequisite to 0.1)

**Why first:** F9. A full `rake` run takes longer than ten minutes, so without this the coverage figure recorded in Stage B is whatever subset of suites happened to finish inside the window.

### A.1 — Fix `.simplecov`

Replace the file with:

```ruby
# The suite runs as four separate processes (units, spec, functionals, features)
# that merge through coverage/.resultset.json. SimpleCov 0.12 discards any stored
# result older than merge_timeout, which defaults to 600s -- so on a full run the
# earliest suites silently drop out and the reported percentage is a fraction of
# the real one. Observed 2026-07-28: a late run produced a report reading 0.0%.
SimpleCov.start 'rails' do
  merge_timeout 3600

  # Each suite must name itself, or CommandGuesser guesses -- and two suites that
  # guess the same name overwrite each other in the resultset. Set by the Rakefile.
  command_name ENV['COVERAGE_SUITE'] if ENV['COVERAGE_SUITE']
end
```

Coverage *filters* are deliberately not added yet — they change the denominator, and Stage B should first reproduce the 72.64% already recorded in `TEST_COVERAGE_PLAN.md`. Reproducing a known number is how you find out the measurement works. Filters land in Stage G.

> `merge_timeout(3600)` runs `seconds.is_a?(Fixnum)`. On Ruby 2.7 that is a deprecated constant (harmless, but it will show up once Stage E turns warnings on). On Ruby 3.2+ `Fixnum` is **gone** and this line raises `NameError` — simplecov 0.12 does not survive the Ruby bump. Not Phase 0's problem; note it for [Phase 2](phase-2-harness-migration.md).

### A.2 — Name each suite in the `Rakefile`

`Rake::TestTask` shells out to a subprocess that inherits the environment, so setting `ENV` in a prerequisite task is sufficient:

```ruby
# Rakefile, above the TestTask definitions
def coverage_suite(name)
  suite_task = "coverage:suite:#{name.downcase.tr(' ', '_')}"
  task(suite_task) { ENV['COVERAGE_SUITE'] = name }
  suite_task
end

Rake::TestTask.new('units' => coverage_suite('Unit Tests')) do |t|
  # ...unchanged
end
```

Apply to `units` (`Unit Tests`), `spec` (`RSpec`), `test:functionals` (`Functional Tests`), and the cucumber tasks (`Cucumber Features`) — matching the names already in `coverage/.resultset.json`, so the historical result stays comparable.

- [ ] `.simplecov` updated
- [ ] Each suite names itself
- [ ] **Verify:** after Stage B, `ruby -rjson -e 'puts JSON.parse(File.read("coverage/.resultset.json")).keys'` lists exactly the expected suites, no `Unknown Test Framework`

---

## Stage B — The baseline run (0.1)

**Do not fix anything during this stage.** The output is a measurement; changing the code mid-measurement invalidates it. Write failures down and move on.

### B.1 — Run everything, log everything

```bash
mkdir -p tmp/baseline
RAILS_ENV=test bundle exec rake                2>&1 | tee tmp/baseline/default.log   # units, spec, functionals, features
RAILS_ENV=test bundle exec rake features:all   2>&1 | tee tmp/baseline/features-all.log
RAILS_ENV=test bundle exec rake features:cli   2>&1 | tee tmp/baseline/features-cli.log
```

Three cucumber runs, not one — F8. `features` is the default-task subset; `features:all` is the honest 53-file denominator; `features:cli` is the nine generator/command files that SimpleCov cannot see.

Expect `features:cli` to be slow and probably red: aruba shells out to `bcms new`, which runs a full `bundle install` inside a generated app, against an `@aruba_timeout_seconds = 15` set at `features/support/env.rb:29`. Record the failure mode rather than fixing it here.

If the default task dies before finishing, run the suites individually (`rake units`, `rake spec`, `rake test:functionals`, `rake features`) so one broken suite does not hide the other three.

### B.2 — Answer the Poltergeist question (F7)

While the features run, confirm the driver is genuinely unused:

```bash
grep -rn '@javascript\|javascript_driver\|Capybara.default_driver\|:poltergeist' features/ test/ spec/
```

If nothing selects Poltergeist and the features pass without PhantomJS installed, **write that down in the baseline** in as many words. It is the most valuable side-finding available in this phase.

### B.3 — Record the baseline

Create `docs/rails-upgrade/phase-0-baseline.md`. This file is exit criteria 4, 6 and 7; it is a deliverable, not a scratchpad.

```markdown
# Phase 0 — Recorded Baseline

**Commit:** <sha>   **Date:** <date>   **Ruby:** 2.7.8   **Rails:** 4.2.11.3
**Command:** `RAILS_ENV=test bundle exec rake` (+ `features:all`, `features:cli`)

## Minitest suites
| Suite | Files | Runs | Assertions | Failures | Errors | Skips |
|---|---|---|---|---|---|---|
| Unit (`test/unit`) | | | | | | |
| Spec (`spec`) | | | | | | |
| Functional (`test/functional`) | | | | | | |
| Orphans (added in Stage D) | | | | | | |

## Cucumber
| Profile | Features | Scenarios | Passed | Failed | Undefined | Skipped |
|---|---|---|---|---|---|---|
| `features` (default: `~@cli ~@known-bug ~@missing-feature`) | | | | | | |
| `features:all` (all 53 files) | | | | | | |
| `features:cli` (`@cli`, 9 files) | | | | | | |

**Cucumber pass rate (all 53 files): __ %**

## Coverage
| | % | Covered | Relevant |
|---|---|---|---|
| Raw (no filters) | | | |
| Filtered (Stage G) | | | |

## Environment findings
- PhantomJS installed: no / yes. Driver actually selected by any scenario: no / yes.
- `RAILS_ENV=test` required: yes (see F1).

## Quarantine register
| Test | Why | Issue |
|---|---|---|
```

- [ ] Three runs completed and logged
- [ ] `phase-0-baseline.md` committed with every cell filled — "unknown" is an acceptable value, an empty cell is not
- [ ] Coverage reproduces ≈72.64% (if it does not, Stage A is wrong — stop and fix it)

---

## Stage C — Stand up CI, red (0.4, part 1)

Land the workflow now, before the suite is green. A GitHub-hosted Ubuntu runner with a fresh Postgres will find environment assumptions that a developer Mac with a warm database never will, and you want those failures in Stage F's queue, not discovered in Stage H.

Remote is `git@github.com:ETBD/browsercms.git`, so Actions is the right target.

### C.1 — `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [master, develop]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: ubuntu-22.04
    timeout-minutes: 45

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_HOST_AUTH_METHOD: trust
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5

    env:
      # test/dummy/config/database.yml defines only `test`; anything that boots
      # the app in `development` aborts with AdapterNotSpecified. See F1.
      RAILS_ENV: test
      # database.yml specifies no host, so libpq falls back to PGHOST -- which
      # points it at the service container instead of a non-existent unix socket.
      PGHOST: localhost
      PGPORT: '5432'
      PGUSER: postgres

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '2.7.8'
          bundler: '1.17.3'
          bundler-cache: true

      - name: Full suite
        run: bundle exec rake

      - name: Cucumber — all features
        run: bundle exec rake features:all

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage
          path: coverage/
          retention-days: 30

  cli-features:
    runs-on: ubuntu-22.04
    timeout-minutes: 45
    continue-on-error: true    # remove or delete this job once Stage F decides — see D2
    services:
      postgres:
        image: postgres:15
        env: {POSTGRES_HOST_AUTH_METHOD: trust}
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5
    env:
      RAILS_ENV: test
      PGHOST: localhost
      PGPORT: '5432'
      PGUSER: postgres
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '2.7.8'
          bundler: '1.17.3'
          bundler-cache: true
      - run: bundle exec rake features:cli
```

Notes on the choices, since each is a place this will otherwise be quietly wrong:

- **`ubuntu-22.04`, pinned — not `ubuntu-latest`.** `ruby/setup-ruby` has no prebuilt 2.7.8 for 24.04. If 22.04 is retired before this lands, switch the job to `container: ruby:2.7.8-bullseye` rather than chasing runner images; the Postgres service works the same way, with `PGHOST: postgres` instead of `localhost`.
- **No PhantomJS install step.** Justified by F7 — and if B.2 disproves it, this is where a `phantomjs` setup step goes.
- **Travis's `--without development` is dropped.** `rake` is declared in the `:development` group (`Gemfile:20`) and the entire chain is rake-driven; installing every group is cheaper than debugging that.
- **`bundle exec rake`, no `RAILS_ENV` prefix**, because the job-level `env:` block sets it. If [D1](#d1-railsenv) resolves toward fixing `database.yml` instead, drop the env var here.
- **`features:all` is a separate step** so the default-subset run and the full run are separately visible in the log.
- **`@cli` in its own `continue-on-error` job**, so the phase can converge while the aruba question is settled independently. Exit criterion 2 is about the main `test` job.

- [ ] Workflow committed and pushed
- [ ] A run appears in the Actions tab (criterion 1) — red is expected and fine at this stage
- [ ] Compare the CI failure list against Stage B's local list; anything CI-only goes in the Stage F queue tagged as environmental

---

## Stage D — Wire in the orphaned tests (0.2)

Ten files, three separate problems (F2, F4, F6).

### D.1 — A fourth `Rake::TestTask` for the reachable orphans

Do **not** use `app:test` (F2). Add to the `Rakefile`:

```ruby
# test/assumptions_test.rb, test/helpers/**, and the eight dummy-app tests under
# test/dummy/test/** are matched by none of the three globs above. rake app:test
# looks like the answer and is not -- it exits 0 having run nothing.
Rake::TestTask.new('test:orphans' => coverage_suite('Orphan Tests')) do |t|
  t.libs << 'lib'
  t.libs << 'test'              # so `require "test_helper"` finds the engine's helper
  t.test_files = FileList[
    'test/*_test.rb',
    'test/helpers/**/*_test.rb',
    'test/dummy/test/**/*_test.rb'
  ]
  t.verbose = false
  t.warning = false             # flipped to true in Stage E
end
```

Add `test:orphans` to the `:test` task's list (`Rakefile:86`), after `test:functionals`.

### D.2 — Fix the one broken require (F4)

`test/dummy/test/unit/portlets/find_category_portlet_test.rb:1` points at a `test/dummy/test/test_helper.rb` that does not exist. Change it to a bare `require "test_helper"` to match its seven siblings. (A shim file in `test/dummy/test/` would also work, and is worse — it invents a second helper for a dummy app that never had one.)

### D.3 — Merge the domain-support tests (F6)

Not duplicates. Move the three real cases from `test/unit/lib/cms_domain_support_test.rb` (`cms_site?` with a `cms` subdomain, with a `www` subdomain, and `cms_domain_prefix`) into `test/unit/lib/cms/domain_support_test.rb`, drop the empty `"prepare_for_rendererable"` stub, and delete the emptied file. Ten cases in, ten cases out — verify the count.

### D.4 — Prove the net is closed (exit criterion 9)

```bash
comm -13 \
  <(RAILS_ENV=test bundle exec rake units spec test:functionals test:orphans TESTOPTS=--verbose 2>/dev/null \
      | grep -o 'test/[^ ]*_test\.rb\|spec/[^ ]*_spec\.rb' | sort -u) \
  <(find test spec -name '*_test.rb' -o -name '*_spec.rb' | sort)
```

Empty output means no file is outside the run. Simpler and equally valid: temporarily add `puts t.file_list.to_a` to each `TestTask` block and diff against `find`.

### Expected damage

| File | What happens | Handle in |
|---|---|---|
| `test/helpers/cms/content_types_helper_test.rb` | Fails — the body is `flunk "Need real tests"` | Stage F / [D4](#d4-flunk-and-stub-tests) |
| `test/assumptions_test.rb` | Fails — asserts an empty DB, `db:install` seeded one (F5) | Stage F / [D3](#d3-assumptions_testrb) |
| The 8 dummy tests | Unknown; never run in living memory | Stage F |
| Coverage | Should **rise** — dummy-app tests exercise `acts_as_content_page`, portlets, design helpers | Re-baseline in Stage G |

- [ ] `test:orphans` defined and in the `:test` chain
- [ ] Broken require fixed
- [ ] Domain-support tests merged, empty file deleted
- [ ] Criterion 9's `find` diff is empty
- [ ] `.resultset.json` has five distinct suite keys, and `Unit Tests` did not shrink (F11)

---

## Stage E — Turn the warnings back on (0.5)

Two independent switches, which the phase file treats as one (F12).

### E.1 — Ruby warnings

Delete `$VERBOSE = nil` from `test/test_helper.rb:29` and its comment. Then flip `t.warning = false` → `true` in every `Rake::TestTask` — leaving the task-level flag off would re-suppress much of what deleting the line was meant to reveal.

Known Ruby-level noise to expect, so it is not mistaken for something new:

- `File.exists?` (deprecated since Ruby 2.1, warns under `-W:deprecated`) — `lib/tasks/core_tasks.rake:51`, `lib/cms/caching.rb:42`, `lib/cms/attachments/attachment_serving.rb:44`, `test/custom_assertions.rb:19`, `lib/generators/cms/content_block/content_block_generator.rb:26`
- `Fixnum` from `merge_timeout` in `.simplecov` (A.1)
- The HTML-parsing warnings from functional tests that the original comment blamed — these are the ones to actually triage

Fix what is cheap (the five `File.exists?` → `File.exist?` are mechanical and safe on 4.2). Silence what is not, **narrowly and with a reason** — a targeted `Warning[:deprecated] = false` around one require, never a blanket `$VERBOSE = nil`.

### E.2 — Rails deprecations in CI

These already print (F12) and are the upgrade roadmap. Add to the workflow's `env:` block:

```yaml
RUBYOPT: "-W:deprecated"
```

`test/dummy/config/environments/test.rb:11` uses `config.serve_static_assets`, removed in Rails 5.0 — that one is already visible today and belongs in [Phase 3](phase-3-backwards-compatible-fixes.md), not here. Phase 0's job is to make the list *visible*, not to work it.

- [ ] `$VERBOSE = nil` gone (criterion 10: `grep -n 'VERBOSE' test/test_helper.rb` is empty)
- [ ] `t.warning = true` on all test tasks
- [ ] `RUBYOPT: "-W:deprecated"` in CI
- [ ] Deprecation output visible in the CI log; no blanket suppression reintroduced

---

## Stage F — Drive to zero failures (0.1, third bullet)

The unbounded stage. Its input is the union of Stage B's local failures, Stage C's CI-only failures, and the new red from Stages D and E.

**The rule, per the phase file: fix it or quarantine it — and a quarantine carries a comment saying why plus a linked issue.** Nothing gets silently skipped.

Suggested triage order, cheapest signal first:

1. **Environmental** (CI-only, missing binaries, DB state) — usually a workflow fix, unblocks the whole board.
2. **Ordering/isolation.** The suite runs two cleaning strategies side by side — transactional rollback for `ActiveSupport::TestCase`, DatabaseCleaner truncation for `Minitest::Spec` — and the comment at `test/test_helper.rb:32-40` documents a real coin-flip this already caused. Suspect any failure that moves when the seed changes. Reproduce with `TESTOPTS="--seed=N"`.
3. **Genuinely broken tests** — fix.
4. **Genuinely broken product code** — this is a finding. Log it; do not fix it inside Phase 0 unless it is trivial.
5. **Cucumber.** Triage by feature file, and treat `@known-bug`-tagged scenarios as pre-quarantined *only if* the tag has an explanation. Five scenarios carry it today.

For each quarantine, add to the test:

```ruby
# QUARANTINED <date>: <one line on why> -- <issue URL>
skip "see <issue>"
```

and a row in the baseline's quarantine register. There are already 20 `skip`s across `test/` and `spec/`; criterion 5 requires each to have a stated reason, so they need reviewing too — that is part of this stage, not an extra.

- [ ] Every failure fixed or quarantined-with-reason
- [ ] The 20 existing skips reviewed and annotated
- [ ] `RAILS_ENV=test bundle exec rake` green locally
- [ ] The main CI job green
- [ ] Baseline document updated with the final numbers and the full quarantine register

---

## Stage G — Make coverage honest (0.3)

Only now, with a green suite and a stable number.

### G.1 — Filters

Append to `.simplecov`:

```ruby
  # Generator templates are copied into a user's app, not executed here.
  # demo.seeds.rb alone is 249 counted lines -- 13.5% of all missed lines -- and
  # loading it would run it.
  add_filter %r{/lib/generators/.*/templates/}
  add_filter %r{/lib/templates/}
```

> **Do not copy the snippet from `TEST_COVERAGE_PLAN.md` §0a verbatim.** It anchors the regex with `^/lib/…`, and SimpleCov 0.12 matches filters against the **absolute** path (`simplecov-0.12.0/lib/simplecov/filter.rb:31`), so the anchored version silently matches nothing — you get a plausible-looking config and an unchanged number. Unanchored, as above.

**Verify:** `grep -c 'demo.seeds.rb' coverage/index.html` → 0, and the percentage moves to roughly 75.8%.

### G.2 — Decide on `lib/generators` ([D2](#d2-libgenerators-coverage))

Five files, 198 counted lines, all 0%, all genuinely exercised by the `@cli` features — out of process, where simplecov 0.12 cannot follow (no `at_fork` before 0.17). Excluding them gives an honest denominator (~78.5%); leaving them in reports a measurement gap as a coverage gap. **Either way, write the decision and its reasoning into the baseline document** — that is what criterion 7 is really asking for.

If excluding:

```ruby
  add_filter %r{/lib/generators/.*_generator\.rb\z}
  add_filter %r{/lib/generators/browser_cms\.rb\z}
```

and record the landmine: `content_block_generator.rb:26` calls `File.exists?`, which no in-process test touches.

### G.3 — Enforce the floor, once

Not `minimum_coverage` in `.simplecov` — F10. Add to `lib/tasks/core_tasks.rake`:

```ruby
namespace :coverage do
  desc 'Fail if merged coverage fell below the recorded Phase 0 baseline'
  task :check do
    require 'json'
    threshold = Float(ENV.fetch('COVERAGE_MINIMUM', '<baseline from G.1/G.2>'))
    path = 'coverage/.last_run.json'
    abort "#{path} missing -- did the suite run?" unless File.exist?(path)
    actual = JSON.parse(File.read(path)).fetch('result').fetch('covered_percent')
    if actual < threshold
      abort format('Coverage %.2f%% is below the %.2f%% baseline.', actual, threshold)
    end
    puts format('Coverage %.2f%% (baseline %.2f%%)', actual, threshold)
  end
end
```

Then, in the `Rakefile`:

```ruby
Rake::Task['ci:test'].enhance { Rake::Task['coverage:check'].invoke }
```

`coverage/.last_run.json` is written unconditionally by simplecov's `at_exit` (`defaults.rb:90`), and — given Stage A's `merge_timeout` — the last suite to finish writes the fully merged figure. The gate runs after the chain, so it cannot fire on a partial merge, and a failing suite short-circuits it (which is correct: a red suite's coverage number is meaningless).

- [ ] Template filters land and demonstrably change the number
- [ ] `lib/generators` decision made **and recorded**
- [ ] `coverage:check` wired into `ci:test`, threshold = measured baseline
- [ ] Baseline document records raw and filtered percentages side by side

---

## Stage H — Close out CI (0.4, rest)

- [ ] Confirm the coverage artifact is downloadable from the run (criterion 7). `coverage/` is gitignored; `upload-artifact` reads the workspace, so this works — just verify it rather than assuming.
- [ ] Resolve the `@cli` job: either it is green and `continue-on-error` comes off, or it stays excluded **and the workflow carries a comment saying why**, mirrored in the baseline (criterion 6 requires the number either way — a documented "9 files, N scenarios, does not run in CI because …" satisfies it; silence does not).
- [ ] `git rm .travis.yml` (criterion 3). Last, so there is a working replacement before the old intent is deleted.
- [ ] Merge to `develop`; confirm the default branch's most recent run is green (criterion 2).
- [ ] Add a CI badge to `README.markdown` — not an exit criterion, but it is the cheapest way to keep criterion 2 true.

---

## 3. Decisions that need a human

### D1: `RAILS_ENV`
`bundle exec rake` is broken without it (F1). Options: **(a)** set `RAILS_ENV=test` in CI and document it as the invocation — smallest change, but the repo's documented command stays broken for developers; **(b)** add a `development:` section to `test/dummy/config/database.yml` pointing at `browsercms_development` — fixes the command for everyone, adds a database CI must create; **(c)** default `RAILS_ENV` to `test` in the `Rakefile` when it is unset — fixes the command everywhere, and is a surprising side effect in a file that also builds gems.
**Recommendation: (a) now, (b) as a follow-up issue.** Phase 0 must measure the suite as it is; changing the database configuration changes what is being measured.

### D2: `lib/generators` coverage
Exclude (honest denominator, ~78.5%, generator regressions stay invisible to the number) versus keep (visible 0% that no reasonable amount of work will move, because the coverage cannot be collected). `TEST_COVERAGE_PLAN.md` §0c recommends excluding and scheduling in-process `Rails::Generators::TestCase` tests later. **Concur** — with the `File.exists?` landmine recorded explicitly so the exclusion is not mistaken for "this code is fine."

### D3: `test/assumptions_test.rb`
It asserts a precondition (empty database) that `db:install` deliberately violates (F5). Either the assumption is stale — delete the file — or it is right and the seeding is the problem, which is a much larger conversation about the two-cleaning-strategies mess documented at `test/test_helper.rb:32-40`. **Recommendation: delete, and open an issue for the fixture-strategy question**, which properly belongs to [Phase 2](phase-2-harness-migration.md).

### D4: `flunk` and stub tests
`test/helpers/cms/content_types_helper_test.rb` is a single `flunk "Need real tests"`. The phase file says write it or delete it, and "no new tests" is also a Phase 0 rule. **Recommendation: delete it, and open an issue** — deleting a file that has never asserted anything removes no coverage, and writing it here would be the one exception to the no-new-tests rule for the least valuable possible test.

---

## 4. Contingencies

| If | Then |
|---|---|
| A large share of Cucumber is red | **Stop and re-scope before Stage F.** This is the finding the README flags as reshaping the whole plan. Report the number, get a decision on repair-versus-retire per feature file, and do not absorb an open-ended repair job inside Phase 0. |
| `ubuntu-22.04` is unavailable | Switch to `container: ruby:2.7.8-bullseye`, `PGHOST: postgres`. Do not upgrade Ruby to satisfy the runner — that is a different project. |
| `features:cli` cannot be made to work in CI | Exclude it, document why in the workflow and the baseline, and still record its local pass rate. Criterion 6 wants the number, not the automation. |
| Coverage does not reproduce ≈72.64% in Stage B | Stage A is wrong, or the four suites are not all reporting. Check `.resultset.json` keys before believing any number (F9, F11). |
| Stage E's warning noise is overwhelming | Land `$VERBOSE`'s removal with `t.warning = false` still set on the tasks, get CI green, then flip the task flags in a follow-up commit. Do not restore `$VERBOSE = nil`. |

---

## 5. Exit criteria traceability

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | Actions workflow exists, runs on push and PR | C | `ls .github/workflows/`; Actions tab shows a run |
| 2 | Most recent run on default branch is green | H | Actions tab |
| 3 | `.travis.yml` gone | H | `test ! -f .travis.yml` |
| 4 | Baseline written down, per suite | B, F | `docs/rails-upgrade/phase-0-baseline.md` |
| 5 | Zero failures; every skip explained | F | CI green; all 20+ skips annotated |
| 6 | Cucumber pass rate known, `@cli` included | B, H | Three profiles recorded in the baseline (F8) |
| 7 | Coverage reported by CI, baseline committed | G, H | Artifact on the run; `coverage:check` threshold matches the baseline |
| 8 | Generator templates excluded | G | `grep -n add_filter .simplecov`; `demo.seeds.rb` absent from the report |
| 9 | No test file outside the run | D | The D.4 `comm` diff is empty |
| 10 | `$VERBOSE = nil` gone, deprecations visible | E | `grep -n VERBOSE test/test_helper.rb` empty; warnings in the CI log |

**A note on criterion 5 versus Stage F:** "zero failing tests" is satisfied by quarantining, and quarantining is not cheating — it is the difference between a known hole and an unknown one. But a phase that quarantines half the Cucumber suite has not met its goal, whatever the checklist says. If that is where this lands, say so in the baseline plainly and take it back to whoever owns the schedule.
