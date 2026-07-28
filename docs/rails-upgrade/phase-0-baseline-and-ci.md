# Phase 0 — Baseline and CI

> ## Goal
> **Establish that the test suite passes, record what it covers, and put that suite behind a CI job that runs on every push.**
>
> Nothing else in this plan can start until this is true. The skill's Step 1 is explicit: *if any tests fail, STOP; do not proceed until all tests pass.*

**Blocking:** 🔴 Yes — gates every other phase.
**Rails version at the end of this phase:** 4.2.11.3 (unchanged).

---

## Why this phase exists

Three reasons, in descending order of how much trouble they cause if skipped:

1. **There is no CI.** The only config is a dead `.travis.yml`; there is no `.github/` directory. Travis OSS is effectively gone, so **browsercms currently has no automated test run at all.** You cannot execute a nine-hop upgrade without a green button — every hop's verification would be someone running `rake` locally and remembering the result.

2. **Nobody knows whether the suite passes.** The most recent commits are `[CMS-420] get tests working` and `[CMS-420] tests are running`. "Running" is not "passing." Every estimate in the supporting documents assumes a green baseline; if it isn't green, the first thing the upgrade would do is mix pre-existing failures with upgrade-induced ones, which is the single most expensive debugging position to be in.

3. **The only end-to-end coverage that exists may already be broken.** 53 Cucumber features, 4,860 lines, running on Poltergeist/PhantomJS — abandoned since 2018. They cover the content-block lifecycle that nothing else covers. If a meaningful share are already red, later phases grow substantially, and it is much cheaper to learn that now than in the middle of a bump.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §6](../../RAILS_UPGRADE_TEST_PRIORITY.md) — "Step 1 — Establish that the suite passes, and get CI. BLOCKING."
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §7](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the coverage-adequacy assessment this phase measures against
- [`TEST_COVERAGE_PLAN.md` §1](../../TEST_COVERAGE_PLAN.md) — the 72.64% figure and its per-file breakdown; §1.1 explains why the headline number is misleading in both directions
- [`TEST_COVERAGE_PLAN.md` §0d](../../TEST_COVERAGE_PLAN.md) — the ten test files currently outside the `rake test` chain
- [`TEST_COVERAGE_ANALYSIS.md` Phase 0](../../TEST_COVERAGE_ANALYSIS.md) — the instrumentation argument, and item 3b on the Cucumber pass rate
- Skill: `workflows/test-suite-verification-workflow.md`, `workflows/ci-sync-workflow.md`

## Work items

### 0.1 — Run everything and write down what happens

- [ ] Run the full default task (`bundle exec rake`, which chains `ci:test` → `db:drop`, `db:create:all`, `db:install`, `test`). Record total / passing / failing / pending per suite: unit, spec, functional, features.
- [ ] Run the `@cli` Cucumber features, which the default task **excludes** via `--tags ~@cli`. These are the generator and command features — nine feature files whose coverage is invisible to SimpleCov because aruba shells out to a child process.
- [ ] Fix or explicitly quarantine every failure. A quarantined test needs a comment saying why and a linked issue; an unexplained skip is a hole in the baseline.

### 0.2 — Wire up the orphaned tests

Ten test files sit outside the `rake test` chain entirely, because the `Rakefile` globs only `test/unit/**/*_test.rb`, `spec/**/*_spec.rb`, and `test/functional/**/*_test.rb`. They split into two kinds:

- **2 are genuinely unreachable** — `test/assumptions_test.rb` and `test/helpers/cms/content_types_helper_test.rb`. No task can run them.
- **8 are reachable but never invoked** — everything under `test/dummy/test/**`. The `Rakefile:15` sets `APP_RAKEFILE` to the dummy app and loads `engine.rake`, so `rake app:test` would run them, but nothing in the `rake test` chain calls it. These cover the engine-host integration path (`acts_as_content_page`, custom portlets, design helpers) — exactly the surface a mountable-engine upgrade threatens.

- [ ] Bring them into the chain, or delete them if they are dead. Either is fine; leaving them unrun is not. See [`TEST_COVERAGE_PLAN.md` §0d](../../TEST_COVERAGE_PLAN.md) for the full list.
- [ ] **Expect this to hurt before it helps.** `test/helpers/cms/content_types_helper_test.rb` is a single `flunk "Need real tests"` and will fail the moment it is wired in. That is the point — a red test is information, an unrun test is not. Either write it or delete it; don't re-hide it.
- [ ] De-duplicate `test/unit/lib/cms_domain_support_test.rb` and `test/unit/lib/cms/domain_support_test.rb` — overlapping tests of the same file.

### 0.3 — Make coverage honest

- [ ] Filter generator *templates* out of coverage in `.simplecov`: `lib/generators/**/templates/`, `lib/templates/`. `demo.seeds.rb` alone is 249 counted lines — 13.5% of all "missed" lines — and it is a seed script that would execute if loaded.
- [ ] Decide what to do about `lib/generators` (5 files, 198 counted lines, all at 0%). They **are** tested, by the `@cli` features, but out of process where SimpleCov cannot see them. Exclude them for an honest denominator and schedule real in-process generator tests later — but record the decision either way.
- [ ] Set `minimum_coverage` to the real measured baseline, so a later phase cannot silently delete tests.

### 0.4 — Stand up CI

- [ ] Port `.travis.yml` to GitHub Actions: Ruby 2.7.8, Postgres, running the same task the default `rake` runs.
- [ ] Include the `@cli` features, or document why they are excluded.
- [ ] Publish the coverage number as a build artifact so the delta is visible per-PR rather than requiring a local run.
- [ ] Delete `.travis.yml` once the Actions workflow is green, so there is exactly one source of truth about how tests run.

### 0.5 — Turn the warnings back on

- [ ] Delete `$VERBOSE = nil` from `test/test_helper.rb`. It suppresses Ruby and Rails deprecation warnings — which are the upgrade roadmap. Fix or explicitly silence the resulting noise; do not restore the blanket suppression.
- [ ] Confirm deprecation output is visible in CI logs (the skill suggests `RUBYOPT="-W:deprecated"`).

---

## Exit criteria

Judge the phase against these. Every one is checkable.

| # | Criterion | How to verify |
|---|---|---|
| 1 | A GitHub Actions workflow exists and runs the suite on push and PR | `ls .github/workflows/` — at least one file; the Actions tab shows a run for the latest commit |
| 2 | The most recent CI run on the default branch is **green** | Actions tab shows a passing run, not a skipped or cancelled one |
| 3 | `.travis.yml` is gone | `test ! -f .travis.yml` |
| 4 | The recorded baseline is written down in the repo, per suite | A committed file (or this doc, updated) states total/passing/failing/pending for unit, spec, functional, and features |
| 5 | Zero failing tests; every skip or quarantine has a stated reason | CI green, plus `grep -rn "skip\|pending" test/ spec/` reviewed — each has a comment |
| 6 | **The Cucumber pass rate is known and recorded**, including the `@cli` features | The number is in the committed baseline. This is the phase's most important output. |
| 7 | Coverage is reported by CI and the number is committed as the baseline | Coverage artifact present on the CI run; `minimum_coverage` set to that number in `.simplecov` |
| 8 | Generator templates are excluded from coverage | `grep -n "add_filter" .simplecov` shows the `templates/` filters |
| 9 | No test file is outside the run | The `Rakefile` patterns plus any additions account for every `*_test.rb` / `*_spec.rb` in the repo; a `find` diff against the run list is empty |
| 10 | `$VERBOSE = nil` is gone and deprecation warnings appear in CI output | `grep -n 'VERBOSE' test/test_helper.rb` returns nothing; warnings visible in the CI log |

**Done means:** a reviewer can open the Actions tab, see green, and read a committed baseline that says exactly how many tests exist, how many Cucumber features pass, and what the real coverage percentage is.

---

## Explicitly not in this phase

- **No Rails version change.** Still 4.2.11.3.
- **No gem upgrades.** `mocha`, `factory_girl`, `capybara` and friends stay pinned — that is Phase 2, scoped by Phase 1's findings. This phase must run the suite *as it is today*, or the baseline measures something other than the current state.
- **No new tests.** Not one. Writing tests before the harness is modernised means writing them twice ([Phase 2](phase-2-harness-migration.md)).
- **No migration off Poltergeist.** This phase only *measures* the Cucumber pass rate. Migrating the driver is Phase 2 work, and the measurement determines how much of it is worth doing.
- **No coverage improvement.** Making the number honest is in scope; making it higher is not.
