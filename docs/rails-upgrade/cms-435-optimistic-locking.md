# CMS-435 — Optimistic locking on versioned content

**Status:** done. **Branch:** `feature/cms-435-optimistic-locking-bug`. **Date:** 2026-09-24.
**Closes:** the follow-up [Phase 4](phase-4-report.md) owed on [D6](phase-4-implementation-plan.md), and the first of the two "worst" items in that report's §8.

---

## 1. Headline

> Two people editing one page no longer silently lose one of the edits. A stale versioned save raises `ActiveRecord::StaleObjectError`, the two controllers that have rescued it for years finally catch one, and the losing editor gets the conflict screen that was already built.
>
> **The ticket anticipated one change. Three were needed**, and each was independently sufficient to keep conflicts invisible. Fixing only the save path would have produced a check with nothing to check against.
>
> Both bundles green: **1143 tests / 2557 assertions / 0 failures** and **156 cucumber scenarios** on 4.2.11.3 and on 5.0.7.2.

The ticket asked for a decision: *should a stale save raise?* The answer is yes, **gated on the caller having supplied `lock_version`**. §4 is the reasoning; §5 is why an ungated raise was not an option.

---

## 2. Why the defect survived this long

`lock_version` has been on every versioned content table since the column was added, and `rescue ActiveRecord::StaleObjectError` has been sitting in [pages_controller.rb:52](../../app/controllers/cms/pages_controller.rb#L52) and [content_block_controller.rb:96](../../app/controllers/cms/content_block_controller.rb#L96) for just as long. Everything looked wired up. Three separate things meant it was not.

### 2.1 The check never ran

ActiveRecord's optimistic locking lives in `_update_record`: it appends the locking column to the `WHERE` of an `UPDATE` against the row, and raises when that matches nothing.

A versioned save never issues one. `create_or_update` ([versioning.rb:395](../../lib/cms/behaviors/versioning.rb#L395)) takes over the update branch and **INSERTs a row into the `_versions` table** instead. The content row's `lock_version` is therefore never part of any `WHERE` clause, the two editors' writes never collide, and AR's check has no opportunity to fire.

This is the part the ticket predicted, and on its own it is the smallest of the three.

### 2.2 There was nothing to check against

Both edit screens load their record through `as_of_draft_version` → `build_object_from_version` ([versioning.rb:21](../../lib/cms/behaviors/versioning.rb#L21)) — `load_draft_page` for pages, `load_block_draft` for blocks.

`lock_version` is in `non_versioned_columns`, so `create_content_table` does not put the column on the `_versions` table at all ([schema_statements.rb:33](../../lib/cms/extensions/active_record/connection_adapters/abstract/schema_statements.rb#L33); asserted by `VERSIONING_COLUMNS` vs `VERSION_TABLE_COLUMNS` in [schema_statements_test.rb:93](../../test/unit/schema_statements_test.rb#L93)). There is no `lock_version` on a version row to copy forward.

So every object built from a version row carried the **column default, 0**, whatever the content row said. The `lock_version` hidden field in both edit forms was always `value="0"`, and the value the browser posted back identified nothing.

The method already knew this. The line

```ruby
#obj.lock_version = lock_version
```

had been sitting there commented out. It could never have worked — there is no `lock_version` on `self` to read.

**Measured before the change:** a page whose content row was at `lock_version` 4 rendered `value="0"`, and `assigns(:page).lock_version` was `0`.

This is why the save path could not be fixed alone. A check against a constant 0 either never fires or always fires.

### 2.3 It also corrupted the number the conflict screen shows

[`_version_conflict_error.html.erb:4`](../../app/views/cms/application/_version_conflict_error.html.erb#L4) tells the user which version their work was based on, and derives it by arithmetic:

```erb
other_version.version - (other_version.lock_version - your_version.lock_version)
```

That is only meaningful if `your_version.lock_version` is the real posted value. With §2.2 in force it is the difference from 0, and the screen would have named the wrong version even once it became reachable.

**Measured after the change:** posted 2, row at 3 → *"Your work was based off **version 2**, while another user Test User has already committed **version 3**."* Correct.

---

## 3. What changed

Four edits, all in [`lib/cms/behaviors/versioning.rb`](../../lib/cms/behaviors/versioning.rb). No controller, view, schema or migration changed — the UI side was already correct once Phase 4 fixed the two partial paths.

| # | Where | Change |
|---|---|---|
| 1 | `build_object_from_version` ([:21](../../lib/cms/behaviors/versioning.rb#L21)) | Read the locking column from the **content row** and write it onto the draft object, replacing the dead commented-out line. Written with `write_attribute` and then `clear_attribute_changes`, so building a draft does not count as a caller supplying a value |
| 2 | the `is_versioned` macro ([:175](../../lib/cms/behaviors/versioning.rb#L175)) | Define a `#{locking_column}=` writer that records `@locking_column_supplied_by_caller` before writing. This is what arms the check |
| 3 | `check_for_stale_lock_version!` ([:309](../../lib/cms/behaviors/versioning.rb#L309)) | New. Re-reads the locking column from the database and raises `ActiveRecord::StaleObjectError` when it has moved |
| 4 | `create_or_update` ([:414](../../lib/cms/behaviors/versioning.rb#L414)) | Call the check in the update branch, **before** the version row is built or saved, and reset the flag afterwards |

Three details worth keeping:

- **The check reads from the database, not from memory.** The whole point is to compare what the editor's browser posted back against what is there *now*. It is a read-then-compare, though, not the atomic `WHERE`-clause check ActiveRecord uses — §10 says what that costs and why the obvious repair is a trap.
- **It runs before the version row is built**, so a conflict leaves no partial write behind.
- **The flag is reset after the save**, so a later save on the same instance is not re-checked against a value the caller never supplied for it.

`sync_locking_column_before_touch` ([:273](../../lib/cms/behaviors/versioning.rb#L273)) — the Phase 4 fix — was **not** changed. Its comment previously opened with *"⚠️ THIS DOES NOT MAKE OPTIMISTIC LOCKING WORK"*; it now says the method is not where conflicts are detected and must not become so, and records that CMS-435 closed the defect without touching it. That method resyncs after the write; this check runs before it.

---

## 4. The decision: raise, but only for callers that supplied the value

The ticket flagged this as the risk, and it is the right thing to have flagged: it changes behaviour on the engine's busiest write path for every caller of a versioned `#save`.

**The gate is: run the check only when a caller has assigned the locking column on this instance.**

That is not a heuristic. It is the one thing that distinguishes the two cases, and it separates them exactly:

| | Assigns `lock_version`? | Behaviour |
|---|---|---|
| A form round-trip (both CMS edit screens) | **yes**, via the hidden field | Checked. Raises on conflict |
| Internal engine code | **never** — see §5.2 | Unchanged from today |
| Downstream application code that does not mention `lock_version` | no | Unchanged from today |
| Downstream code that opts in by assigning it | yes | Checked |

The last two rows are the compatibility story, and they are why this is a safe change to ship. An application built on this engine keeps today's behaviour unless it explicitly asks for the new one. There is no configuration flag, because assigning the column *is* the opt-in.

---

## 5. Why an unconditional raise was not an option

### 5.1 `PageComponent#save` is stale by design

[`Cms::PageComponent#save`](../../app/models/cms/page_component.rb#L17) — the Mercury inline-editing path — loads a page, updates each block on it, then saves the page. Each block update copies the page's connectors forward, which **bumps the page**. By the time the page itself is saved, the in-memory copy is behind the database.

**Measured: in-memory 3 against database 4, every time, with no second editor anywhere near it.** An unconditional check turns every inline edit into a false conflict.

The two cases are not distinguishable by comparing values — both are "in-memory is behind the database". What separates them is *where the value came from*.

This is not a theoretical concern: it is [sabotage 3](#7-sabotage) below, and removing the gate produces 7 errors.

### 5.2 Nothing internal assigns the column

The gate only works if internal code really never assigns `lock_version`. Checked across the whole engine:

```
$ grep -rn "lock_version" app/ lib/ --include='*.rb' --include='*.erb'
```

Outside `versioning.rb` and the schema helper, every hit is one of: the two form templates that render the hidden field, the two conflict partials that read it for display, or `content_type.rb:114` which **excludes** it from a list of attribute names. **No Ruby code in `app/` or `lib/` assigns it.** The only writers are the form round-trips, which is precisely the intended set.

### 5.3 Is `lock_version` even a faithful conflict signal?

Worth asking, because it is bumped by more than direct edits. Checked two cases that could have produced false conflicts:

- **Editing a connected block on the page.** Moves the page's `lock_version` 3→4 *and* its draft version 3→4, in lockstep. The page a second editor is holding really is out of date, and the conflict is legitimate.
- **Saving an unrelated sibling page.** Does not touch the page at all.

So the signal is faithful. No case was found where `lock_version` moves without the held copy genuinely being stale.

---

## 6. The caller survey the ticket asked for

Every versioned model in the engine and the dummy app, with `locking_enabled?` measured rather than read off the schema:

**Engine (9):** `Cms::Attachment`, `Cms::FileBlock`, `Cms::Form`, `Cms::HtmlBlock`, `Cms::ImageBlock`, `Cms::Link`, `Cms::Page`, `Cms::PagePartial`, `Cms::PageTemplate`.

**Dummy app / test fixtures (6):** `Dummy::Catalog`, `Dummy::DeprecatedInput`, `Dummy::Product`, `HasManyAttachments`, `HasThumbnail`, `VersionedAttachable`.

**Locking is enabled on all 15** — `create_content_table` adds `lock_version` to every content table, so versioned and locking-enabled are the same set. There is no versioned type that this change cannot reach, and none that needed exempting.

⚠️ `Cms::Form` is removed entirely on `feature/cms-434-forms-subsystem` (production has zero forms, zero entries). That branch drops one row from this table and changes nothing else here; the two branches do not interact.

---

## 7. Sabotage

Per the Phase 4 convention — and its hard-won rule that a sabotage must be *verified to have taken effect* before its result is believed. Each was applied to a clean tree and reverted with a byte-for-byte comparison afterwards.

| Sabotage | Unit | Functional |
|---|---|---|
| 1 — remove the `check_for_stale_lock_version!` call from `create_or_update` | **5 failures** | **5 failures** |
| 2 — `build_object_from_version` stops reading the content row | 1 failure, **6 errors** | 2 failures, **5 errors** |
| 3 — the check becomes unconditional (gate removed) | **7 errors** | 0 — all pass |

Sabotage 3 is the informative row. Removing the gate leaves **every functional test passing**; it is caught only by the unit file, and specifically by the `PageComponent` test. A test suite that covered only the conflict screen would have signed off on a change that made every Mercury inline edit a false conflict. That is the whole reason §5.1 is pinned at the behaviour level rather than through the controller.

---

## 8. Tests

**[`test/unit/behaviors/versioning_locking_test.rb`](../../test/unit/behaviors/versioning_locking_test.rb)** — 18 runs, 21 assertions.

The Phase 4 characterization test `"CHARACTERIZATION: a stale save silently overwrites a concurrent edit"` pinned the *defect*, and its own failure message said that its failing was the signal to do this work. It was deleted, and the section header that replaces it records the three-part finding. Eleven tests replace it, covering: a stale save raises; the first editor's content survives; a rejected save writes no version row; a draft carries the content row's real `lock_version`; building a draft does not arm the check; a stale save that never supplied a value still proceeds; supplying a value arms the check; supplying a *current* value saves normally; the armed state does not carry over to a later save; creating with a `lock_version` does not raise; the check applies to content blocks as well as pages; and the `PageComponent` inline-edit flow raises no false conflict.

**[`test/functional/cms/version_conflict_test.rb`](../../test/functional/cms/version_conflict_test.rb)** — 8 runs, 19 assertions.

Phase 4 created this file for the two broken partial paths in `_main_form.html.erb`, and had to **stub** the trigger — `Cms::Page.any_instance.stubs(:save).raises(...)` — because no ordinary save could raise. **The stub is gone.** Every test now drives two real editors and a real conflict. Three tests were added: the losing edit does not overwrite the winning one; an ordinary edit with a current `lock_version` still succeeds; and the edit form carries the content row's real `lock_version`.

Two test-side notes worth not rediscovering:

- `assert_select "input#x[value=?]", v, "message"` does **not** do what it looks like. The `?` consumes `v`, and the trailing string is then read as the element's expected *text content* — so the assertion fails against a perfectly correct form. The message belongs in the options hash: `count: 1, message: "..."`.
- `assert_nothing_raised` takes no arguments on 5.0 (deprecated) and none at all on 5.1. The explanation goes in a comment.

---

## 9. Results

| Suite | 4.2.11.3 | 5.0.7.2 |
|---|---|---|
| `rake units` | 849 runs, 1944 assertions, **0F 0E**, 4 skips | 849 runs, 1944 assertions, **0F 0E**, 4 skips |
| `rake spec` | 145 runs, 260 assertions, **0F 0E**, 7 skips | 145 runs, 260 assertions, **0F 0E**, 7 skips |
| `rake test:functionals` | 142 runs, 344 assertions, **0F 0E**, 9 skips | 142 runs, 344 assertions, **0F 0E**, 9 skips |
| `rake test:orphans` | 7 runs, 9 assertions, **0F 0E** | 7 runs, 9 assertions, **0F 0E** |
| `rake features` | 156 scenarios, 847 steps, **all passed** | 156 scenarios, 847 steps, **all passed** |

Identical counts on both bundles is exactly what Phase 1's **false green** warning describes, so it was checked rather than assumed: a probe test printing `Rails.version` from inside the spawned rake subprocess reports `4.2.11.3` under `Gemfile` and `5.0.7.2` under `Gemfile.next`. The dual boot is genuine and the green is real.

---

## 10. Deliberately not changed

- **The conflict screen itself.** It was already built, already tested, and — since Phase 4 fixed the two partial paths — already working. It had simply never been reachable. Nothing in this ticket touched a view.
- **`sync_locking_column_before_touch`.** See §3.
- **The `content_block_controller` conflict path** beyond confirming it rescues the same error. It shares `check_for_stale_lock_version!` and is covered at the behaviour level by the content-block test in the unit file; it has no equivalent of the pages functional test.
- **The last millisecond of the race.** The check is read-then-compare: `SELECT` the locking column, compare in Ruby, raise or proceed. ActiveRecord's own mechanism is stronger — it puts the comparison *inside* the `UPDATE`'s `WHERE` and infers the conflict from the affected row count, so the losing writer cannot pass. This one cannot borrow that, because §2.1 is precisely that a versioned save issues no `UPDATE` against the content row to hang a `WHERE` on.

  So under PostgreSQL's default READ COMMITTED, two saves landing within the same few milliseconds can both read the same value, both pass, and both proceed. **Known and accepted.** The exposure is not what it replaces: the old behaviour lost the edit *unconditionally*, at any spacing, whereas this loses it only in a genuine race — and when it does, the outcome degrades to that old behaviour rather than to anything worse.

  ⚠️ The obvious repair is a compare-and-swap — `UPDATE ... WHERE id = ? AND lock_version = ?`, incrementing, then checking the affected count. **It is wrong here**, and the reason is not obvious: `touch` already increments the locking column (`activerecord-4.2.11.3/lib/active_record/persistence.rb:470`) via the after-save `touch_self_and_ancestors`, so a CAS would increment twice per save. That breaks the lockstep between `lock_version` and `version` that the conflict screen's arithmetic depends on (§2.3), reintroducing the wrong-version-number bug by another route. The shape that works is a row lock — `.lock` on the read, leaving the incrementing to the touch — and it needs the deadlock question answered first, since `touch_self_and_ancestors` walks up and touches every ancestor section inside the same transaction.

- **Any schema change.** Adding `lock_version` to the `_versions` tables would be another way to solve §2.2 and a worse one: it duplicates a column whose authority is the content row, and every existing installation would need a migration.
