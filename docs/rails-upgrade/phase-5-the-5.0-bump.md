# Phase 5 — The Rails 5.0 Bump

> ## Goal
> **Make Rails 5.0 the default version, with the suite green, CI matching the new Gemfile, and `load_defaults` handled as a deliberate decision rather than a side effect.**
>
> By this point every known breakage has already been fixed on 4.2. This phase should be small. If it isn't, an earlier phase was incomplete.

**Blocking:** — (this is the payoff, not a gate)
**Rails version at the end of this phase:** **5.0.x**, deployed.

---

## Why this phase exists

Everything before this was preparation designed to make the bump boring:

- [Phase 0](phase-0-baseline-and-ci.md) gave a green button and a known baseline.
- [Phase 1](phase-1-gem-compatibility-and-dual-boot.md) proved Rails 5.0 boots and named every blocking gem.
- [Phase 2](phase-2-harness-migration.md) got the suite passing on `Gemfile.next` — **so Rails 5.0 is already green before this phase starts.**
- [Phase 3](phase-3-backwards-compatible-fixes.md) removed ~96 breakages while still on 4.2.
- [Phase 4](phase-4-characterization-tests.md) pinned the behaviour that changes silently.

So the actual bump is mostly bookkeeping: swap the constraint, retire the dual-boot scaffolding *or* keep it for the next hop, sync CI, and decide the `load_defaults` question — which for an engine is genuinely different from what the skill's guide assumes.

**The one thing that is not bookkeeping** is `load_defaults`. See §5.4.

## Supporting documentation

- [`RAILS_UPGRADE_TEST_PRIORITY.md` §6, Phase 4](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the version-by-version rules, including CI sync and the per-hop patch re-check
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §0.3](../../RAILS_UPGRADE_TEST_PRIORITY.md) — **the engine `load_defaults` problem.** The most important section for this phase.
- [`RAILS_UPGRADE_TEST_PRIORITY.md` §7](../../RAILS_UPGRADE_TEST_PRIORITY.md) — the coverage-adequacy table, whose ❌ rows are the honest known-risk list to verify manually
- Skill: `version-guides/upgrade-4.2-to-5.0.md` — the hop guide, including the `belongs_to` migration checklist and common issues
- Skill: `references/testing-checklist.md` — **the source for the manual verification in §5.5**
- Skill: `workflows/ci-sync-workflow.md` — mandatory before the PR
- Skill: `workflows/app-update-preview-workflow.md` — for reviewing config changes before applying them
- Skill: the `rails-load-defaults` skill (§5.4), the `upgrade-cleanup` plugin (§5.6)

## Work items

### 5.1 — Swap the version

- [ ] Update `browsercms.gemspec`: `s.add_dependency "rails", "~> 4.2.0"` → `"~> 5.0.0"`.
- [ ] Bring across every gem bump from Phase 1's required-bumps bucket.
- [ ] `bundle update rails`. Confirm the resolved version is the **latest 5.0 patch**, not 5.0.0 — the skill's Step 0 applies at every hop, and starting a hop on an old patch means debugging bugs that were already fixed.
- [ ] Verify `rails console` and `rails server` work against the dummy app, and that the homepage renders. These are the skill's post-`bundle update` smoke checks and they catch boot-level problems before the suite obscures them.

### 5.2 — Review the config changes

- [ ] Generate an `app:update` preview and review each proposed config change individually rather than accepting wholesale. As an engine, most app-level config belongs to `test/dummy`, not to BrowserCMS itself — be deliberate about which changes are the engine's and which are the dummy app's.
- [ ] Confirm the `config.public_file_server.enabled` rename from [Phase 2](phase-2-harness-migration.md) is still correct under the real 5.0.

### 5.3 — Sync CI

- [ ] Enumerate every CI file and diff Ruby version, Rails matrix, and service versions against the upgraded Gemfile. The skill calls stale CI the **most common cause of red builds on upgrade PRs**.
- [ ] The default job now runs 5.0. Decide what `Gemfile.next` points at: either retire it, or repoint it at **5.1** to keep dual-boot rolling into the next hop. Keeping it is the cheaper path if you're continuing immediately.

### 5.4 — Decide `load_defaults` — the real work of this phase

The skill's Step 7 says: after the version bump, delegate to the `rails-load-defaults` skill and walk each config change one risk tier at a time, re-running tests between each.

**That assumes an application. BrowserCMS is an engine**, and `load_defaults` appears nowhere in this repo (`lib/cms/engine.rb:7` declares `isolate_namespace Cms`). The flag values are owned by the **host app** — `cms`, and every other downstream BrowserCMS project.

So the question is not "which defaults do we adopt?" It is **"which range of host `load_defaults` values does BrowserCMS claim to support?"**

- [ ] Make that decision and write it down — in the README, the gemspec description, or a `SUPPORT.md`. It's a contract with downstream projects, not an internal config choice.
- [ ] For each behaviour the decision touches, ensure the test suite covers **both** settings, or state explicitly that only one is supported. [Phase 4](phase-4-characterization-tests.md)'s `belongs_to_required_by_default = true` test env is the template.
- [ ] Set `deprecation_behavior = :raise` in the test environment from 5.0 onward, so the next hop's deprecations surface as failures rather than log noise.
- [ ] **Do not fix deprecation warnings about Rails 5.1+ behaviour during this hop.** Those belong to the next cycle. Triaging tomorrow's warnings today expands scope and risks shipping something half-finished. Record them for [Phase 6](phase-6-subsequent-hops.md).

### 5.5 — Verify manually where tests can't

The [§7 coverage-adequacy table](../../RAILS_UPGRADE_TEST_PRIORITY.md) has four ❌ rows. Those are known-uncovered areas, so they need eyes. From the skill's `references/testing-checklist.md`:

- [ ] **Auth / authorization** — log in, log out, password reset, role-based access. The permission join-models are untested and `persistent_user.rb` (209 LOC) has no test at all; **permissions failing *open* is the worst possible upgrade regression.**
- [ ] **Content-block CRUD end to end** — create, edit, publish, connect to a page, render on the public page, view version history, revert.
- [ ] **File upload / download / image variants** — Paperclip is still in place, but this is the public upload path.
- [ ] **Forms** — submission, validation display, CSRF. `form_entries_controller.rb` is 140 lines at **0% coverage** and handles public form submission.
- [ ] **Assets** — CSS, JS, images load; fingerprinting and compilation work.
- [ ] Record the results. An unrecorded manual pass is indistinguishable from no manual pass.

### 5.6 — Ship it

- [ ] Deploy and monitor. The skill's rollback triggers: error rate > 2× normal, response time > 3× normal, a critical feature broken, or any data-integrity issue.
- [ ] **Do not auto-run cleanup.** The `upgrade-cleanup` plugin removes `NextRails.next?` branches and retires dual-boot scaffolding, but only when explicitly asked. If you're heading straight to 5.1, keeping dual-boot in place is the right call.

---

## Exit criteria

| # | Criterion | How to verify |
|---|---|---|
| 1 | `Gemfile.lock` resolves the **latest 5.0 patch** | `bundle list \| grep " rails "`; cross-check against RubyGems for the newest 5.0.x |
| 2 | `browsercms.gemspec` declares `~> 5.0.0` | `grep -n 'add_dependency("rails"' browsercms.gemspec` |
| 3 | **Full suite green on 5.0** — unit, spec, functional, and features | CI passing on the default job |
| 4 | Coverage at or above the Phase 4 number | Coverage artifact compared against Phase 4's |
| 5 | **Cucumber pass rate at or above Phase 0's baseline** | Compare against the committed number. Regression here means the end-to-end net shrank during the upgrade. |
| 6 | `rails console` and `rails server` both work; the dummy app's homepage renders | Manual, recorded |
| 7 | CI config matches the upgraded Gemfile — Ruby version, Rails matrix, services | Every CI file diffed; the skill's ci-sync verdict is OK with no DRIFT entries |
| 8 | **The `load_defaults` support decision is written down** in a durable place | The statement exists in the repo and names which host `load_defaults` values are supported |
| 9 | `deprecation_behavior = :raise` is set in the test environment | `grep -rn "deprecation_behavior" test/dummy/config/environments/test.rb` |
| 10 | The manual verification checklist from §5.5 is **completed and recorded**, including an explicit auth/permissions pass | A committed note with per-item results |
| 11 | Deprecation warnings emitted by 5.0 about 5.1 behaviour are **captured, not fixed** | A committed list, carried into [Phase 6](phase-6-subsequent-hops.md) |
| 12 | Deployed to production and stable past the skill's rollback window | No rollback trigger fired |
| 13 | Zero `NextRails.next?` branches were needed for application code | `grep -rn "NextRails" app/ lib/` — if any exist, each needs a comment saying why the fix couldn't be version-neutral |

**Done means:** criteria 3, 5, 7, 8, and 10 all hold. Green tests alone are not sufficient — the Cucumber rate must not have regressed, CI must actually match the Gemfile, the engine's `load_defaults` contract must be stated, and someone must have logged in and confirmed permissions still deny.

> **If this phase turned out to be hard, that is diagnostic information.** It means [Phase 1](phase-1-gem-compatibility-and-dual-boot.md), [3](phase-3-backwards-compatible-fixes.md), or [4](phase-4-characterization-tests.md) was incomplete. Record what surprised you before starting 5.1 — the same gap will bite again.

---

## Explicitly not in this phase

- **No 5.1 work.** Not `*_filter` (already done in Phase 3), not `redirect_to :back` (verified absent), not the 5.1 deprecations this hop surfaces. One hop at a time; the skill is emphatic that **version skipping is not allowed.**
- **No Zeitwerk, no `ApplicationRecord`.** Both are 6.0.
- **No Paperclip, Devise config, SimpleForm, or asset-pipeline migration.**
- **Not fixing forward-looking deprecation warnings** (criterion 11). Capture them; fix them in the hop that owns them.
- **No dual-boot cleanup**, unless you've decided to stop here. If 5.1 is next, keep the scaffolding.
- **No coverage improvement.** Holding the line is the goal.
