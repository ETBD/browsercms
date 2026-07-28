# Phase 1 — Gem Compatibility and Dual-Boot

> ## Goal
> **Produce a definitive, data-backed list of which gems block Rails 5.0 — and be able to boot the app under both 4.2 and 5.0 from the same working copy.**
>
> This phase replaces guesswork about gem EOL with resolver output, and it must come *before* the harness migration because its findings determine how much of that migration is actually forced.

**Blocking:** 🔴 Yes — scopes [Phase 2](phase-2-harness-migration.md), and no bump can happen without dual-boot.
**Rails version at the end of this phase:** 4.2.11.3 still boots and is still the default. `Gemfile.next` resolves to 5.0.

---

## Why this phase exists

**Because hand-reasoning about gem compatibility has already produced a wrong answer, and the tooling produces a right one.**

The supporting analysis correctly identified that Paperclip is EOL, `factory_girl` was renamed, and `mocha 1.2.0` predates the `mocha/setup` removal. What it *couldn't* see by reading Gemfiles was this:

`lib/cms/content_filter.rb:12` calls `HTML::FullSanitizer`. That constant does not exist in Rails 4.2. It comes from `rails-deprecated_sanitizer (1.0.4)`, which is in the bundle only because `rails-dom-testing (1.0.9)` depends on it — and `rails-dom-testing 1.x` is capped at `activesupport < 5.0`. **The moment Rails 5 resolves, `rails-dom-testing` jumps to 2.x, `rails-deprecated_sanitizer` leaves the bundle, and that line raises `NameError`.** The file is 100% covered, so coverage says it's safe. A grep for Rails APIs says it's safe. Only actually resolving the bundle and booting reveals it.

That is one instance of a class of failure — a gem that resolves cleanly but calls or requires something that no longer exists. The skill has two dedicated steps for exactly this (4.5 and 4.6), and this phase is those steps.

The dual-boot half exists because every subsequent phase needs to answer "does this change work on both versions?" without swapping Gemfiles by hand.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §6](../../RAILS_UPGRADE_TEST_PRIORITY.md) — "Step 2 — Set up dual-boot" and "Step 4.5 / 4.6 — Gem compatibility and boot smoke test"
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.2, ➕A3](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the `HTML::FullSanitizer` finding in full
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §3, B4](../../RAILS_UPGRADE_TEST_PRIORITY.md) — why Paperclip is a Step 4.5 question rather than a judgement call
- [`TEST_COVERAGE_ANALYSIS.md` §5.4](../../TEST_COVERAGE_ANALYSIS.md) — dependency gates, including the `cms`-side Rails LTS and Gem Fury sources
- Skill: `workflows/gem-compatibility-workflow.md` (the primary check and when to escalate), `workflows/boot-smoke-test-workflow.md`, `references/gem-compatibility.md` (the fork/vendor/replace playbook — load only if blockers appear)
- Skill: the `dual-boot` skill, for `next_rails --init` and the `NextRails.next?` pattern

## Work items

### 1.1 — Set up dual-boot

- [ ] Add `next_rails` and run `next_rails --init` to generate `Gemfile.next`. Check first that no `Gemfile.next` exists, to avoid a duplicate `next?` method definition.
- [ ] Configure the `Gemfile` / `browsercms.gemspec` with `if next?` conditionals so both versions resolve.
- [ ] Install dependencies for both: default and `BUNDLE_GEMFILE=Gemfile.next`.
- [ ] Add a second CI job that runs the suite against `Gemfile.next`, **allowed to fail** for now. Its output is the running scoreboard for the rest of the upgrade.

**One rule for all later phases:** when a fix genuinely cannot work on both versions, branch on `NextRails.next?`. Never `respond_to?` or other feature detection. Most fixes in [Phase 3](phase-3-backwards-compatible-fixes.md) need no branch at all.

### 1.2 — Run the compatibility check (Step 4.5)

- [ ] Run `bundle_report compatibility` per the skill's workflow against the target Rails version. Escalate to the railsbump API only under the conditions that workflow specifies.
- [ ] Sort every gem into three buckets: **required bumps**, **blockers**, **already compatible**. Commit the result — later phases reference it.
- [ ] At minimum, the following need a verdict. Every one is currently pinned to a version that predates Rails 5:

| Gem | Pinned | Why it's on the list |
|---|---|---|
| `paperclip` | 5.0 (gemspec) | EOL 2018; the whole attachment subsystem depends on it |
| `mocha` | 1.2.0 | `mocha/setup` removed in 2.0; **109** call sites |
| `factory_girl` / `factory_girl_rails` | 4.7.0 | Renamed `factory_bot` in 2017; **42** references |
| `cucumber` / `cucumber-rails` | 2.4.0 / 1.4.5 | 53 features depend on it |
| `capybara` | 2.10.1 | Selector semantics changed in 3.0 |
| `poltergeist` | 1.11.0 | PhantomJS, abandoned 2018 |
| `database_cleaner` | 1.5.3 | Split into `database_cleaner-active_record` 2.x |
| `aruba` | 0.14.14 | Hard-pinned; drives the `@cli` features |
| `simplecov` | 0.12.0 | 2016; no branch coverage, so every figure so far is line-only |
| `rails-dom-testing` | 1.0.9 | **Capped at `activesupport < 5.0`.** The `HTML::FullSanitizer` chain. |
| `compass-rails`, `sass-rails` | — | Compass EOL 2018 |
| `jquery-rails` | 3.1 | Far behind |
| `devise` | ~> 4.0 | Skill's guide wants 4.2+ for Rails 5; also the only thing supplying `responders` |

- [ ] If any gem lands in **blockers**, load `references/gem-compatibility.md` and decide fork / vendor / replace per gem. Write the decision down; do not leave it implicit.

### 1.3 — Boot smoke test (Step 4.6)

- [ ] Run a Rails-loading command against `Gemfile.next`: `BUNDLE_GEMFILE=Gemfile.next bundle exec rake -T`, or `bin/rails runner "puts Rails.version"`, or `rspec --dry-run` — anything that triggers `Bundler.require` and the framework boot.
- [ ] For each `LoadError` / `NoMethodError` / `NameError`: identify the offending gem, check RubyGems for a version with target-Rails compatibility, and add the bump to the required-bumps bucket.
- [ ] **Confirm `HTML::FullSanitizer` in `lib/cms/content_filter.rb:12` surfaces here.** If the smoke test passes without flagging it, the smoke test isn't loading enough of the app — fix the test, not the expectation.
- [ ] Re-run until Rails boots under `Gemfile.next`. Booting is the bar; the suite passing is [Phase 5](phase-5-the-5.0-bump.md).

### 1.4 — Record what the check changed

- [ ] Note any place where the compatibility data contradicts the supporting documents, and update them. The analysis docs were written from working knowledge; this phase produces measurements, and measurements win.

---

## Exit criteria

| # | Criterion | How to verify |
|---|---|---|
| 1 | `Gemfile.next` exists and resolves | `test -f Gemfile.next && BUNDLE_GEMFILE=Gemfile.next bundle check` |
| 2 | `Gemfile.next` resolves to a Rails 5.0.x | `BUNDLE_GEMFILE=Gemfile.next bundle list \| grep " rails "` |
| 3 | **The default bundle still resolves to 4.2.11.3 and the suite is still green** | `bundle list \| grep " rails "`; CI green on the default job |
| 4 | Rails **boots** under `Gemfile.next` | `BUNDLE_GEMFILE=Gemfile.next bundle exec rake -T` exits 0 |
| 5 | A committed three-bucket gem report exists: required bumps / blockers / already compatible | The file is in the repo and every gem in the table above appears in exactly one bucket |
| 6 | Every gem in the **blockers** bucket has a written fork/vendor/replace decision | Each blocker has a named owner-decision in the report, not a question mark |
| 7 | The `HTML::FullSanitizer` breakage is confirmed by the smoke test and recorded | The smoke-test output naming it is committed alongside the gem report |
| 8 | A CI job runs against `Gemfile.next` | `.github/workflows/` contains a job with `BUNDLE_GEMFILE=Gemfile.next`; it may be failing, but it must run and report |
| 9 | No `respond_to?`-style version branching was introduced | `grep -rn "respond_to?(:.*Rails\|Rails::VERSION" app/ lib/` returns nothing new |

**Done means:** you can state, from a committed artifact rather than from memory, exactly which gems must move before Rails 5 and which of those have no compatible version — and Rails 5.0 boots, even though the suite doesn't pass yet.

---

## Explicitly not in this phase

- **No Rails bump on the default Gemfile.** 4.2.11.3 stays the default through Phase 4.
- **Not making the suite pass under `Gemfile.next`.** Booting is the bar. The suite failing there is expected and is precisely what [Phase 2](phase-2-harness-migration.md) fixes.
- **No Paperclip replacement.** Deciding whether it's ActiveStorage, Shrine, or `kt-paperclip` is in scope; *doing* it is not. Paperclip's 5.x line works on Rails 5, so the migration belongs near the 7.2 → 8.0 hop where Propshaft and ActiveStorage land together.
- **No Devise upgrade.** Its verdict is recorded here; the work is Phase 2 (test helpers) and Phase 5 (config).
- **No code fixes.** Even the `HTML::FullSanitizer` line — this phase *finds* it, [Phase 3](phase-3-backwards-compatible-fixes.md) fixes it.
