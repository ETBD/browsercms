# BrowserCMS Rails Upgrade — Phase Plan

**Target:** Rails 4.2.11.3 → Rails 8.x, sequentially, one minor version at a time.
**Scope of these files:** the pre-bump work and the **first hop only (4.2 → 5.0)**. Hops 5.1 through 8.0 are handled by repeating [Phase 6](phase-6-subsequent-hops.md).
**Repo:** `browsercms` (the engine). The consuming `cms` app has its own blockers; they are noted where they gate this work but are not planned here.

---

## How to read a phase file

Every file has the same five sections, in this order:

| Section | What it answers |
|---|---|
| **Goal** | One sentence. If you read nothing else, read this. |
| **Why this phase exists** | The specific risk it retires. |
| **Work items** | The concrete changes, with counts and `file:line` references. |
| **Exit criteria** | A checklist where **every item is objectively verifiable** — most have a command next to them. This is how you judge whether the goal was reached. |
| **Explicitly not in this phase** | Deferred work, so a reviewer can tell a gap from an oversight. |

**A phase is complete when every exit criterion passes — not when the work items are done.** Work items are the plan; exit criteria are the contract. If a work item turns out to be unnecessary, that's fine. If an exit criterion can't be met, the phase isn't finished.

---

## The phases

| # | Phase | Goal in brief | Blocking? | Status |
|---|---|---|---|---|
| **0** | [Baseline and CI](phase-0-baseline-and-ci.md) | Know the true pass rate and get a green button that runs on every push | 🔴 **Yes** — nothing else can start | ✅ **Done** — [plan](phase-0-implementation-plan.md) · [results](phase-0-baseline.md) |
| **1** | [Gem compatibility and dual-boot](phase-1-gem-compatibility-and-dual-boot.md) | Find out which gems actually block Rails 5, and be able to boot both versions | 🔴 **Yes** — its output scopes Phase 2 | ✅ **Done** — [plan](phase-1-implementation-plan.md) · [results](phase-1-gem-report.md) |
| **2** | [Harness migration](phase-2-harness-migration.md) | Make the test suite capable of running on Rails 5, while still on 4.2 | 🔴 **Yes** — the suite cannot boot on Rails 5 today | ⚠️ **Done, 11 of 12 criteria** — [plan](phase-2-implementation-plan.md) · [results](phase-2-harness-report.md) |
| **3** | [Backwards-compatible code fixes](phase-3-backwards-compatible-fixes.md) | Land ~96 mechanical changes that work on 4.2 *and* 5.0+, shrinking the bump diff | 🟡 Strongly recommended — but it owns the five defects keeping CI red | 📋 **Planned** — [plan](phase-3-implementation-plan.md) |
| **4** | [Characterization tests](phase-4-characterization-tests.md) | Pin the behaviour that Rails 5 changes *silently*, before it can drift | 🔴 **Yes** for the four 5.0-specific items | — |
| **5** | [The 5.0 bump](phase-5-the-5.0-bump.md) | Rails 5.0 green, deployed, with `load_defaults` handled deliberately | — | — |
| **6** | [Subsequent hops](phase-6-subsequent-hops.md) | A repeatable checklist for 5.1 → 5.2 → 6.0 → … → 8.0 | — | — |

**Phase 0 is done with two caveats**, both about the default branch rather than the work: its exit criteria 1 and 2 ask for a green CI run on the *default* branch, and the work currently sits on `feature/cms-420-migrate-tests`. CI triggers are now `master`, `develop` and pull requests, so those two close when this merges into `develop` — not before.

**Phase 2 is done, with criterion 3 unmet and knowingly so.** The harness migration itself is complete: the 4.2 suite is green at 78.35% (the number moved because simplecov moved, not because coverage did — see the [report](phase-2-harness-report.md)), and on Rails 5 the unit suite went from 323 errors to 3 while cucumber went from "does not load" to 154 scenarios collected. What remains red on Rails 5 is five *application* defects that no harness work can reach, and they belong to Phase 3. The `next-rails` CI job was made gating anyway, deliberately, so **CI is red on every PR until Phase 3 lands** — the job's comment names all five.

Phase 2's original Poltergeist migration had nothing to migrate (Phase 0 established that no Capybara driver is ever selected), and Phase 1 showed most of the gems it planned to move carry no Rails 5 cap. Both were dropped. The report also records six places the plan was wrong, including two that broke the 4.2 suite before being caught.

**Ordering note:** Phase 1 comes before Phase 2 deliberately. The gem compatibility check determines how much of the harness migration is actually forced, so running it first prevents Phase 2 from being scoped on guesswork.

Phases 3 and 4 can run in parallel — Phase 3 is mechanical and Phase 4 requires thought, so they compete for different attention rather than the same hands.

---

## Supporting documentation

These phase files are a distillation. The reasoning, evidence, and per-file coverage data live here:

| Document | What it holds |
|---|---|
[`RAILS_UPGRADE_TEST_PRIORITY.md`](../../RAILS_UPGRADE_TEST_PRIORITY.md) | **The primary source.** Breakage risk ranked by *silence* rather than likelihood. §0 carries the skill reconciliation verdicts, §3 the Tier B silent-change items (B1–B10), §4 the Tier C loud ones, §5 the verified-clean list, §7 the coverage-adequacy assessment. |
| [`TEST_COVERAGE_PLAN.md`](../../TEST_COVERAGE_PLAN.md) | Real measured coverage (72.64%), per-file, ordered by coverage-gained-per-unit-effort. The secondary lens for sequencing *within* a phase. |
| [`TEST_COVERAGE_ANALYSIS.md`](../../TEST_COVERAGE_ANALYSIS.md) | The wider gap analysis across both repos, including the `cms` integration surface and the content-block lifecycle gap. Its estimates were superseded by `TEST_COVERAGE_PLAN.md`; its *structural* findings still stand. |

### The `rails-upgrade` skill

The methodology behind this plan (FastRuby.io, *The Complete Guide to Upgrade Rails*). Not in this repo — it lives in the `ombulabs-ai` checkout at `rails-upgrade/3.3.0/rails-upgrade/`. Files referenced by these phases:

- `SKILL.md` — the mandated step order, and the rule that **version skipping is not allowed**
- `version-guides/upgrade-4.2-to-5.0.md` — the hop these phases build toward
- `workflows/test-suite-verification-workflow.md` — Phase 0
- `workflows/gem-compatibility-workflow.md`, `workflows/boot-smoke-test-workflow.md` — Phase 1
- `workflows/ci-sync-workflow.md` — Phase 0 and every hop's PR
- `references/testing-checklist.md` — the exit-criteria source for Phase 5
- `detection-scripts/patterns/rails-*.yml` — the per-version detection patterns, re-run at every hop in Phase 6

---

## Two things that were unknown — now measured

Both were called out here as the questions the downstream estimates depended on. Phase 0 answered them. Full numbers in [`phase-0-baseline.md`](phase-0-baseline.md).

1. **Does the suite pass?** **Yes.** 994 Minitest tests, 0 failures, 0 errors, 19 skips — every skip carrying a stated reason. Coverage 75.82%, enforced by `rake coverage:check`.
2. **Are the 53 Cucumber features green?** **Mostly, and the exceptions are concentrated.** 154/154 in the default profile. Across all 53 files it is 161/193 — and **27 of the 29 failures are the `@cli` set**, which shares a single root cause: `rails new` failing inside aruba. The remaining two are tagged `@known-bug` and `@missing-feature`.

The third answer nobody asked for is the most useful one: **Poltergeist was never in play.** There are no `@javascript` tags anywhere and both Capybara driver assignments are commented out, so the suite is green on a runner with no browser installed. The "abandoned since 2018" driver risk that shaped Phase 2's scope does not exist.

So the plan does **not** change shape the way this section feared — with one exception. The `@cli` features are the only coverage `lib/generators` has, and they are 79% red going into a sequence of hops that rewrite generator APIs. That is the gap to close, and it is tracked as O1 in the baseline rather than buried here.

Effort estimates from the source documents were **not** revisited during distillation and are deliberately omitted from these files. Sequence and exit criteria are the useful parts; days-per-phase should be estimated by whoever picks up the work, now that Phase 0 has reported real numbers.
