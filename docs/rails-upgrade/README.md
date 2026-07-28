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

| # | Phase | Goal in brief | Blocking? |
|---|---|---|---|
| **0** | [Baseline and CI](phase-0-baseline-and-ci.md) | Know the true pass rate and get a green button that runs on every push | 🔴 **Yes** — nothing else can start |
| **1** | [Gem compatibility and dual-boot](phase-1-gem-compatibility-and-dual-boot.md) | Find out which gems actually block Rails 5, and be able to boot both versions | 🔴 **Yes** — its output scopes Phase 2 |
| **2** | [Harness migration](phase-2-harness-migration.md) | Make the test suite capable of running on Rails 5, while still on 4.2 | 🔴 **Yes** — the suite cannot boot on Rails 5 today |
| **3** | [Backwards-compatible code fixes](phase-3-backwards-compatible-fixes.md) | Land ~96 mechanical changes that work on 4.2 *and* 5.0+, shrinking the bump diff | 🟡 Strongly recommended |
| **4** | [Characterization tests](phase-4-characterization-tests.md) | Pin the behaviour that Rails 5 changes *silently*, before it can drift | 🔴 **Yes** for the four 5.0-specific items |
| **5** | [The 5.0 bump](phase-5-the-5.0-bump.md) | Rails 5.0 green, deployed, with `load_defaults` handled deliberately | — |
| **6** | [Subsequent hops](phase-6-subsequent-hops.md) | A repeatable checklist for 5.1 → 5.2 → 6.0 → … → 8.0 | — |

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

## Two things that are still unknown

Stated plainly, because most of the estimates downstream depend on them and neither has been measured:

1. **Whether the suite currently passes.** `git log` shows `[CMS-420] tests are running`. "Running" is not "passing." Phase 0 answers this.
2. **Whether the 53 Cucumber features are green.** They are the only end-to-end coverage that exists anywhere, and they run on Poltergeist/PhantomJS, abandoned since 2018. Phase 0 answers this too.

If a large share of the Cucumber suite is already red, the plan changes shape — so both questions are inside Phase 0 rather than deferred.

Effort estimates from the source documents were **not** revisited during distillation and are deliberately omitted from these files. Sequence and exit criteria are the useful parts; days-per-phase should be estimated by whoever picks up the work, after Phase 0 reports real numbers.
