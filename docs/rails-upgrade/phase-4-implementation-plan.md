# Phase 4 — Implementation Plan

**Implements:** [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md)
**Exit criteria:** all **14** live in [`phase-4-characterization-tests.md` § Exit criteria](phase-4-characterization-tests.md#exit-criteria), not in this file. This plan references them by number throughout; [§7](#7-exit-criteria-traceability) maps each to the stage that meets it.
**Entry condition:** Phase 3 complete at 14 of 14 criteria ([report](phase-3-report.md)) — `Gemfile` green at 1007 tests, 0F/0E, cucumber 154/154, line **78.37%** / branch **70.83%**; `Gemfile.next` at **10** failures across unit, functional and cucumber, and the `next-rails` job gating and red.
**Rails at the end of this phase:** `Gemfile` still 4.2.11.3 and green. `Gemfile.next` **green** — this is the phase where the `next-rails` job stops being red, and unlike Phase 3 that claim is scoped to work this phase actually owns.

Same shape as the [Phase 0](phase-0-implementation-plan.md), [Phase 1](phase-1-implementation-plan.md), [Phase 2](phase-2-implementation-plan.md) and [Phase 3](phase-3-implementation-plan.md) plans: findings first, then an ordered work stream, then the decisions that need a human.

**Local prerequisites, established during planning:** both bundles install clean under Ruby 2.7.8 / Bundler 1.17.3 with no lockfile drift (`BUNDLE_FROZEN=true bundle install`, and the same with `BUNDLE_GEMFILE=Gemfile.next`), Postgres is reachable on the socket `test/dummy/config/database.yml` expects, and the dual-boot assertion reports `Booted Rails 5.0.7.2`.

> ### Read this first
>
> Four things moved before any code was written, and two of them change what the phase is:
>
> 1. **Work item 4.1 is largely already built.** Phase 3's stage-B audit test is a 224-line, 9-test enumeration of all 29 `belongs_to` declarations, and its own closing comment says *"Phase 4 owns the permanent version of this."* What remains is one missing assertion and a criterion that needs rewriting — not a day of work. ([1.1](#11-work-item-41-is-substantially-already-built), [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one))
> 2. **Criterion 3 cannot be met as written, and criteria 3 and 11 contradict each other.** Forcing `belongs_to_required_by_default` on is a no-op on 5.0 in the shape the phase document imagines, and raises `NoMethodError` on 4.2. Phase 3 measured this and the finding never made it back into the phase file. ([1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it))
> 3. **B1 — the item ranked first in the whole analysis — has a wrong premise, and the correction makes it much worse.** `ColumnDumper` was *not* removed at 5.0. The patch does not evaporate; it **wins**, with the wrong arity, against a caller that passes one argument. **Measured end to end: on the 5.0 bundle the schema dumper emits 0 of 74 tables and exits successfully.** The 4.2 control emits 73. This is not a latent risk — it is a live, total, silent failure, and it has already happened once in this repo. ([1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50), [1.6](#16-criterion-8s-guard-would-not-have-caught-15))
> 4. **One of the three "singletons" in Phase 3's residue is a nine-site class**, and the failing test is a truthiness bug rather than the cast bug it was filed as. ([1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug))
>
> The net effect is that **the phase is not smaller, it is differently shaped**: less `belongs_to` work than planned, considerably more schema-dumper work, and one work item (4.0) that arrived from Phase 3 and carries the red CI job.

---

## 1. Pre-flight findings

Every measurement below was taken against this tree. Gem source references are to the installed gems (`/Users/…/gems/2.7.0/gems/`), because `vendor/bundle` is not present locally — paths in the older plans point there and no longer resolve.

### 1.1 Work item 4.1 is substantially already built

[`test/unit/belongs_to_optionality_test.rb`](../../test/unit/belongs_to_optionality_test.rb) is 224 lines and nine tests, added by Phase 3's stage B. It already does what 4.1 asks for, by a better mechanism than 4.1 proposes:

| 4.1 asks for | The audit test already does |
|---|---|
| "For each of the **29** declarations, one test that either asserts required or asserts saves-without-it" | A verdict table (`AUDIT` + `BEHAVIOR_AUDIT`) with one entry per site, and **six** invariant tests over it — every site has a verdict, every verdict names a live association, `:required` sites are backed by a presence validation *and* left bare, `:optional` sites carry `required: false` *and* are not contradicted by a presence validation |
| "Pay particular attention to the 5 injected by behaviors" | `test "userstamping and categorizing inject required: false everywhere they apply"` checks them **where they land** — `Cms::Page`, `Cms::HtmlBlock`, `Cms::Section` — not just on the behavior module |
| — | A both-bundles probe: `test "required: false adds no presence validation on either bundle"` |

The counts reconcile: `AUDIT` holds 24 entries (7 `:required`, 17 `:optional`), `BEHAVIOR_AUDIT` holds 3, and two more are declared dynamically — 29. The 7 bare plus 22 carrying `required: false` matches the [Phase 3 report's](phase-3-report.md) criterion-2 row exactly.

**What is actually left of 4.1** is [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one) and the criterion rewrites in [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) and [1.3](#13-criterion-4s-literal-check-does-not-match-the-audit-tests-design). Budget hours, not the day the phase file implies.

### 1.2 Criterion 3 rests on a misreading, and Phase 3 already measured it

Criterion 3: *"`belongs_to_required_by_default = true` is set in the test environment — without this, criterion 4 is meaningless."* Work item 4.1 opens with the same instruction in bold.

The reasoning behind it is wrong, and the audit test's header comment documents why in detail. The flag is read inside `ActiveRecord::Associations::Builder::BelongsTo.define_validations` (`activerecord-5.0.7.2/lib/active_record/associations/builder/belongs_to.rb:122`) and its entire effect is one line — `model.validates_presence_of reflection.name, message: :required`. That runs when `belongs_to` is **called**, at class-definition time. So:

- Setting the flag in a `setup` block cannot retroactively add validations to associations already defined. **It is a no-op even on 5.0.**
- The accessor does not exist on 4.2 at all — it arrives at `activerecord-5.0.7.2/lib/active_record/core.rb:117` — so touching it **raises `NoMethodError` on the production bundle.**

Setting it in `test/dummy/config/environments/test.rb` *would* take effect on 5.0, because that runs before models autoload. But it still raises on 4.2, so it needs a version guard — and the guard would live under `test/`, which **criterion 11 forbids** (`grep -rn "NextRails" test/ spec/` stays empty). **Criteria 3 and 11 cannot both be satisfied.** [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant) resolves it.

Verified absent: `grep -rn "belongs_to_required_by_default" test/ spec/ lib/ config` returns **one hit, a comment** in the audit test.

### 1.3 Criterion 4's literal check does not match the audit test's design

Criterion 4: *"A test file enumerates them; the count in the test matches 29."*

The audit test enumerates by **reflection** over 15 named classes plus three behavior-injected names, which is strictly better — it catches a `belongs_to` added tomorrow, which a hardcoded list of 29 would not. But no literal `29` appears anywhere in it, so the criterion's stated check fails against a test that over-satisfies its intent. Either add a count assertion as a tripwire or amend the criterion; [D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite) picks the former, because the count is genuinely useful as a review anchor.

### 1.4 One declaration has no assertion, and it is a dynamic one

Two of the 29 are declared dynamically, which is why `grep` cannot audit them:

- `lib/cms/behaviors/versioning.rb:115` — version → parent. **Asserted**, through `Cms::HtmlBlock::Version.reflect_on_association(:html_block)`.
- `lib/cms/behaviors/dynamic_attributes.rb:168` — `base_class`. **Not asserted anywhere.**

The audit test's comment names both as needing reflection-based assertions and then only writes one. This is the single concrete gap in 4.1, and it is the more dangerous of the two to leave: `dynamic_attributes` is applied per-model by consumers, so a downstream project on `load_defaults 5.0` is the one that finds out.

### 1.5 B1 is an arity collision, not a vanishing monkeypatch, and it is live on 5.0

This is the most consequential finding in the phase and it inverts the item's stated failure mode.

[`RAILS_UPGRADE_TEST_PRIORITY.md` §3 B1](../../RAILS_UPGRADE_TEST_PRIORITY.md) ranks [`lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb`](../../lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb) first in the whole analysis, on this reasoning:

> *"`ColumnDumper` was folded into `SchemaDumper` in the Rails 5.1–6.0 range… when the target module no longer exists, `module ActiveRecord::ConnectionAdapters::ColumnDumper` does not fail. It silently defines a brand-new, empty module that nothing includes. The patch evaporates."*

The ranking is right. The mechanism is wrong. Measured:

| | 4.2.11.3 | 5.0.7.2 |
|---|---|---|
| `ColumnDumper` exists | ✅ `abstract/schema_dumper.rb:8` | ✅ **still `abstract/schema_dumper.rb:8`** |
| Included by the adapter | ✅ `abstract_adapter.rb:73` | ✅ **still, `abstract_adapter.rb:71`** |
| `def column_spec` | `(column, types)` — arity **2** | `(column)` — arity **1** |
| `def prepare_column_options` | arity **2** | arity **1** |
| Caller | — | `schema_dumper.rb:140` — `@connection.column_spec(column)` |

So the module is not gone at 5.0 and the patch does not evaporate. It does the opposite: **it wins, and it wins with the wrong signature.** Measured on both load orders (patch-then-adapter, and adapter-then-patch), on 5.0:

```
column_spec now defined at: …/browsercms/lib/cms/extensions/…/schema_dumper.rb
arity: 2
```

and simulating the real call from `schema_dumper.rb:140` against an object including the module:

```
ArgumentError: wrong number of arguments (given 1, expected 2)
```

Two things close the escape hatches:

- **`PostgreSQL::ColumnDumper` does not shadow it.** `activerecord-5.0.7.2/lib/active_record/connection_adapters/postgresql/schema_dumper.rb` defines `column_spec_for_primary_key`, `prepare_column_options`, `migration_keys`, `default_primary_key?`, `schema_type` and `schema_expression` — **not `column_spec`**. So the abstract module's method, i.e. the patch's, is what the PG adapter calls.
- **Loading is unconditional.** [`lib/cms/extensions.rb`](../../lib/cms/extensions.rb) is `Dir[…/extensions/**/*.rb].each { |f| require f }`. There is no version guard and no opt-out on either bundle.

#### Confirmed end to end

Both bundles were installed and the real dumper run against the live `browsercms_test` database (74 tables), output captured to a `StringIO` so `db/schema.rb` was never touched:

| | 4.2.11.3 (control) | 5.0.7.2 |
|---|---|---|
| Tables in the database | 74 | 74 |
| `create_table` statements emitted | **73** | **0** |
| Tables reported as undumpable | 0 | **72** |
| `published` / `deleted` / `archived` columns dumped | **123** | **0** |
| Process outcome | success | **success** |

In the booted 5.0 app the live `PostgreSQLAdapter` resolves `column_spec` to the patch (`arity: 2`, `source_location` = the patch file), and every table fails the same way:

```
# Could not dump table "catalogs" because of following ArgumentError
#   wrong number of arguments (given 1, expected 2)
```

**And nothing raises.** `ActiveRecord::SchemaDumper#table` (`activerecord-5.0.7.2/lib/active_record/schema_dumper.rb:102-104`) wraps the per-table body in `begin … rescue => e` and writes the exception into the stream **as a comment**. So `rake db:migrate` on the 5.0 bundle exits 0 and writes a syntactically valid `schema.rb` in which all 74 tables are commented out.

This is worse than B1 predicted in every dimension: not partial but **total**, not loud but **silent**, and not future but **now**.

#### This resolves the §9 contradiction rather than standing against it

[`phase-3-report.md` §9](phase-3-report.md) records that `app:test:prepare` rewrote `test/dummy/db/schema.rb` during Phase 3, "dropping ~500 lines of dynamically-created test tables and reformatting it in 5.0's style," and that it was reverted. That was not a formatting difference. **That was this bug**, observed as a cosmetic artifact and filed as one. The file was reverted, so no damage persisted — but the detection was luck, and the note that came out of it ("watch `schema.rb` before every commit") treats the symptom.

So the two observations agree, and B1 is confirmed as the correct top-ranked item in the analysis — for a mechanism nobody had identified.

### 1.6 Criterion 8's guard would not have caught 1.5

Criterion 8: *"A guard test fails if `ColumnDumper` is undefined at load time. Temporarily rename the constant in the patch file; the guard test must go red."*

`ColumnDumper` **is** defined at 5.0. A guard that asserts the constant exists passes on both bundles while the dumper is broken on one of them. The criterion tests for the failure mode B1 predicted rather than the one that is actually present.

B1's own prescription is better than the criterion derived from it: *"Assert on the dumped output, not on `column_spec`'s return value — the point is to detect the patch going missing, so the test must exercise the real dumper end to end."* Follow the item, not the criterion. [D3](#d3--what-criterion-8s-guard-must-actually-assert) rewrites it.

⚠️ **And the measurement in [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50) rules out one more test shape that looks sufficient and is not.** Because `SchemaDumper#table` rescues into a comment, the dump **succeeds** while emitting nothing. So a test that asserts "dumping does not raise" passes on the broken bundle, and so does one that asserts the output is non-empty — the 5.0 dump is 234 lines of header and error comments. **The assertion has to be on dumped content**: a `create_table` count, and the boolean-default columns by name.

### 1.7 B3 / criterion 6 is partly done

[`test/unit/schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) already exists with six tests over `create_content_table` / `add_content_column`:

- `:version_foreign_key` silently ignored
- non-versioned blocks create no versions table
- default versioned column created for subclasses
- non-existent models get a default versions table
- `create_content_table` makes two tables
- `add_content_column` adds to both tables

Criterion 6 wants "**every** option combination… and asserts the resulting column set on both the content table and the `_versions` table." What is missing is the `name:` option and a per-combination assertion of the full column set rather than of one column's presence. That is an extension of an existing file, not a new one.

### 1.8 B6's three questions all answer "no" — the audit is already done

B6 asks for an audit before test-writing, and budgets "a day for reading" to answer three questions about [`test/unit/behaviors/versioning_test.rb`](../../test/unit/behaviors/versioning_test.rb). Grepped:

| Question | Assertion present? |
|---|---|
| Does a failed validation produce no new version? | **No** — no assertion in the file mentions `valid` or `invalid` |
| Does `version_comment` reflect *this* save's changes? | **No** — `version_comment` appears in no assertion |
| Does a rolled-back transaction leave no orphan version row? | **No** — neither `transaction` nor `rollback` appears |

All three need writing, so the reading budget can be cut and the item becomes three concrete tests. The 96.91% line coverage on `versioning.rb` is exactly the "tested for the wrong thing" case B6 warns about, now confirmed rather than suspected.

This item also has a live claim behind it: `versioning.rb:206-225` is a comment block documenting an **observed** `save` call order, and Phase 3 changed `save!` in that same file to forward `(*args, &block)` ([Phase 3 §5](phase-3-report.md)). These three tests are the net that change should have had.

### 1.9 The `tasks_controller` failure is one of nine sites, and it is a truthiness bug

[Phase 3 §6](phase-3-report.md) files `Cms::TasksControllerTest#test_complete_no_tasks` as a singleton: *"`PG::InvalidTextRepresentation: invalid input syntax for type integer: \"\"`. Rails 5 stopped coercing `\"\"` to nil on integer casts."* The diagnosis stops one step short.

The test ([`tasks_controller_test.rb:52`](../../test/functional/cms/tasks_controller_test.rb#L52)) does `put :complete, params: {:task_ids => nil}`. The controller ([`tasks_controller.rb:21-23`](../../app/controllers/cms/tasks_controller.rb#L21)):

```ruby
def complete
  if params[:task_ids]
    Task.where(["id in (?)", params[:task_ids]]).each do |t|
```

On 4.2 the nil arrives as `nil` — falsy — and the `else` branch runs. On 5.0 it arrives as `""` — **truthy** — so the `if` branch runs and hands `""` to Postgres as an integer. The cast error is the symptom; **the guard is the defect.** `if params[:task_ids]` asks "was the key present?" when it means "is there a value?"

That pattern is not unique to this controller. Nine sites guard on the truthiness of a params value:

| Site | |
|---|---|
| [`attachments_controller.rb:13`](../../app/controllers/cms/attachments_controller.rb#L13) | `if params[:version]` |
| [`content_block_controller.rb:128`](../../app/controllers/cms/content_block_controller.rb#L128) | `if params[:version]` |
| [`content_block_controller.rb:219`](../../app/controllers/cms/content_block_controller.rb#L219) | `if params[model_form_name]` |
| [`toolbar_controller.rb:14`](../../app/controllers/cms/toolbar_controller.rb#L14) | `if params[:page_id]` |
| [`inline_content_controller.rb:20`](../../app/controllers/cms/inline_content_controller.rb#L20) | `if params[:container]` |
| [`tasks_controller.rb:22`](../../app/controllers/cms/tasks_controller.rb#L22) | `if params[:task_ids]` ← **the one the suite happens to hit** |
| [`pages_controller.rb:74`](../../app/controllers/cms/pages_controller.rb#L74) | `if params[:page_ids]` |
| [`sections_controller.rb:68`](../../app/controllers/cms/sections_controller.rb#L68) | `if params[:section_id]` |
| [`users_controller.rb:15`](../../app/controllers/cms/users_controller.rb#L15) | `unless params[:show_expired]` |

Four of the nine feed the value straight into a finder or an integer column, so they have the same shape as the failing one. **This is a Tier B silent-change item that arrived disguised as a single red test** — which is a good argument for why it belongs in this phase and not in Phase 3.

### 1.10 The missing partial is a real 4.2 bug with a one-line fix

Confirmed on both halves. [`app/views/cms/pages/_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2):

```erb
<%= render :partial => 'cms/shared/version_conflict_error', :locals => {…} %>
```

`app/views/cms/shared/` exists and holds `access_denied.html.erb`, `error.html.erb`, `error.xml.erb` — **no version-conflict partial**. `find app/views -name "*version_conflict*"` returns exactly two files, both under `app/views/cms/application/`. So the reference is broken on **both** bundles; 4.2 never renders that branch, and 5.0 does only because the update ahead of it fails.

Fixing it will not make the two functional failures pass — it changes what they say. That ordering matters and is easy to get backwards.

### 1.11 No eager-load test exists, and the test environment has eager loading off

`grep -rn "eager_load" test/ spec/ lib/cms/engine.rb` finds only the three dummy-app environment settings, and [`test/dummy/config/environments/test.rb:17`](../../test/dummy/config/environments/test.rb#L17) is `config.eager_load = false`. So 4.2's test must call `Rails.application.eager_load!` explicitly — which is what B10 prescribes anyway.

The surface it defends is larger than the supporting docs state. [`lib/cms/engine.rb:112-116`](../../lib/cms/engine.rb#L112) pushes **9 paths in 5 statements** (the analysis says "6 directories"):

```ruby
ActiveSupport::Dependencies.autoload_paths += %W( #{self.root}/vendor #{self.root}/app/mailers #{self.root}/app/helpers)
ActiveSupport::Dependencies.autoload_paths += %W( #{self.root}/app/controllers #{self.root}/app/models #{self.root}/app/portlets)
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/portlets )
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/presenters )
ActiveSupport::Dependencies.autoload_paths += %W( #{Rails.root}/app/portlets/helpers )
```

Note the last three are `Rails.root`, not `self.root` — **host application** directories, which an engine cannot see the contents of at test time. Zeitwerk has no `autoload_paths` API at all, so all nine statements are 6.0 work; this test is what will size it.

`require_dependency` is confirmed as exactly one site — [`content_types_controller.rb:1`](../../app/controllers/cms/content_types_controller.rb#L1) — and the file is 0% covered, so the eager-load test is also the only thing that will ever load it.

### 1.12 B9's four target sites are confirmed, and two are in files with no test at all

Line numbers re-verified against this tree (Phase 3 moved several):

| Site | Current line | Coverage |
|---|---|---|
| `pages_controller.rb` `strip_visibility_params` | **124-128** (was 126-128) | 3 lines untested |
| `sections_controller.rb` `delete('group_ids')` | **43** | in the 9 missed lines |
| `form_fields_controller.rb` `delete(:form_id)` | **16** | **0% file** |
| `forms_controller.rb` `delete(:new_entry)` | **33** | **0% file** |

`ls test/functional/cms/ | grep -i form` returns **nothing** — there is no functional test file for either Forms controller. Both are 0% because nothing instantiates them, so criterion 7 ("no longer 0%") needs the files created, not extended.

Two of the four sit on an authorization boundary: `strip_visibility_params` is a `before_action` on `:create`/`:update` ([`pages_controller.rb:10`](../../app/controllers/cms/pages_controller.rb#L10)) that removes fields a non-admin must not set, and `sections_controller.rb:43` drops `group_ids` unless `current_user.able_to?(:administrate)`. A `Parameters`-semantics change here fails **open**.

### 1.13 The residue reconciles to ten, and the phase-4 target is therefore ten

Recorded here because Phase 3's report said "nine" in four places and the enumeration said ten; the count has since been corrected in that report. Per-suite, against [§2](phase-3-report.md):

| Suite | Failures | Composition |
|---|---|---|
| unit | 1F / 2E | 2× `StaleObjectError` (cluster) + `test_publish_on_save` |
| functional | 0F / 3E | 2× missing partial (cluster) + `test_complete_no_tasks` |
| cucumber | 4 failed | 2× `manage_images` + 1× `sitemap/pages` (cluster) + `portlets_with_params` |

**7 cluster + 3 singletons = 10**, and the per-suite split matches the measured totals exactly.

---

## 2. Execution order

Stage A first is not the obvious choice — it is not one of the ten failures, and criterion 13 is what the phase is judged on. It goes first because **[1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50) is now a confirmed, live, silent data-corruption bug**: on the 5.0 bundle the schema dumper emits 0 of 74 tables and exits successfully. Every day it stays unfixed is a day someone can run `db:migrate` on `Gemfile.next` and commit an empty schema that looks fine in review.

Stage B does not depend on it — the test database is built from migrations, not from `schema.rb` — so this is a judgement about severity, not sequencing. If you want criterion 13 moving sooner, A.2 alone (the one-line scope fix) can land first and A.3/A.4's tests can trail stage B. **What must not happen is A.2 trailing the phase.**

| Stage | Work item | Why here |
|---|---|---|
| **A** | B1 / criterion 8 | Settles [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50). Until this is known, no 5.0 number is trustworthy |
| **B** | **4.0** | The ten failures. Owns criterion 13 and the red CI job. Longest stage; starts as soon as A clears the ground |
| **C** | 4.2 | The eager-load test. One hour, largest signal-per-hour in the plan, and independent of everything else — do it while B is still being diagnosed |
| **D** | 4.1 | `belongs_to` — close the [1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one) gap and land the criterion rewrites. Small |
| **E** | 4.3 | `create_content_table` option matrix. Extends an existing file |
| **F** | 4.4 | `Parameters` on the four uncovered sites. Creates two test files that do not exist |
| **G** | 4.6, B.2 | B6's three versioning tests. The audit is already done ([1.8](#18-b6s-three-questions-all-answer-no--the-audit-is-already-done)). Also carries B.2's partial fix, deferred out of stage B |
| **H** | 4.5, 4.7 | Schema-dumper end-to-end assertion (folded into A's fix), B7 `publish!`, B8 `default_scope`. ⚠️ This row omitted **B2**, the `dynamic_attributes` chain, which work item 4.7 also lists — recovered during the stage from the phase document |
| **I** | 4.7 (Tier C), — | **Tier C's three error branches**, recovered in the stage-H audit and folded in here rather than carried to Phase 5. Then exit: both suites, coverage on a cleared resultset, criteria table |

**Run the 4.2 suite after every stage, not at the end.** Phase 3's deviation 8 is the cautionary tale: a "pure rename" broke three 4.2 tests because they were mocha expectations on the renamed method, and it was only caught because the plan said to re-run. This phase writes tests that assert on framework internals, which is the same category of fragility.

---

## 3. Stage detail

### A — Settle the schema-dumper contradiction and fix B1 ✅

**A.1 — ✅ Done during planning. The dumper is broken on 5.0; see [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50).** Result: 0 of 74 tables dumped, 72 reported undumpable in comments, process exits 0. The 4.2 control emits 73 tables and 123 boolean-default columns. `db/schema.rb` was not touched (output captured to a `StringIO`). Both bundles are now installed, and the dual-boot assertion reports `Booted Rails 5.0.7.2`.

Kept below for the record, and because the same commands are how you verify A.2's fix:

```bash
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake db:drop db:create:all db:install
BUNDLE_GEMFILE=Gemfile.next RAILS_ENV=test bundle exec rake db:migrate   # this dumps
git diff --stat test/dummy/db/schema.rb
```

The outcome was the third of the three this stage was scoped against — *"dump succeeds but the output is short on tables"* — in its most extreme form: short by **all** of them. Treat any 5.0 `schema.rb` produced before A.2 lands as worthless rather than merely suspect.

**The ten failures in stage B are not affected by this.** The test database is built by `db:install` from migrations, not from `schema.rb`, so the schema in the database is correct even though the dumped file is not. A and B are independent; A goes first because it is the larger defect, not because B depends on it.

⚠️ **Do this on a clean tree and revert `test/dummy/db/schema.rb` afterwards.** [Phase 3 §9](phase-3-report.md) warns that the suite rewrites this file; that warning applies double to a stage whose whole purpose is to run the dumper.

**A.2 — ✅ Done. Fix the patch.** The patch exists to work around a Ruby 2.7 frozen-string crash in **4.2's** `column_spec`, which mutated option strings in place with `String#insert`. 5.0's implementation already builds a new string (`Hash[prepare_column_options(column).map { |k, v| [k, "#{k}: #{v}"] }]`), so **5.0 does not need the patch at all.** The fix is to stop applying it there, guarded with `if ActiveRecord::VERSION::MAJOR < 5` per [D4](#d4--how-to-scope-the-schema-dumper-patch).

Measured immediately after, by the same method as A.1:

| | 4.2.11.3 | 5.0.7.2 |
|---|---|---|
| `column_spec` arity | 2 (the patch) | 1 (Rails' own) |
| `create_table` emitted | 73 | **72** — was **0** |
| Tables reported undumpable | 0 | **0** — was **72** |
| Boolean-default columns | 123 | **123** — was **0** |

The one-table difference is `ar_internal_metadata`, a Rails 5 bookkeeping table its own dumper ignores and 4.2 does not know to skip. Nothing to do with the patch; A.3's test accounts for it explicitly.

**A.3 — ✅ Done. The end-to-end assertion** (criterion 9, and B1's actual prescription), in [`test/unit/schema_dumper_test.rb`](../../test/unit/schema_dumper_test.rb). Dump the schema for a content table and assert the output contains `published`, `deleted` and `archived` with their defaults. Assert on the **dumped string**, not on `column_spec`'s return value. This is the test that detects the patch being wrong in either direction, on either bundle.

**A.4 — ✅ Done. The guard, proven in both directions** (criterion 8, as rewritten by [D3](#d3--what-criterion-8s-guard-must-actually-assert)). Asserts the *signature* the patch expects is the signature the framework calls with — not that a constant exists — plus that the override is in effect on 4.2 and **not** on 5.0.

Broken deliberately in both directions, per the criterion's own instruction:

| Sabotage | Bundle | Result |
|---|---|---|
| Guard widened to `if true` (the original defect) | 5.0 | 🔴 **5 of 6 failed** — *"72 of 72 tables are missing from the dump"* |
| Guard narrowed to `if false` (patch removed) | 4.2 | 🔴 **5 of 6 failed** — *"44 of 72 tables are missing"* |

The 4.2 number is worth keeping: **44 of 72** is the file comment's *"missing half its tables"*, reproduced on demand. The original bug is now a test you can run rather than a story in a comment.

- [x] A real 5.0 dump has been run and its outcome recorded — [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50)
- [x] `test/dummy/db/schema.rb` unchanged — md5 identical before and after the full 4.2 and 5.0 unit runs
- [x] The dumped-output test asserts **content**, and explicitly rejects the three weaker shapes that pass against the broken dumper (see the test's header comment)
- [x] Passes on **both** bundles: 6 runs, 12 assertions, 0F/0E each
- [x] The guard has been seen red — in both directions

**Stage A regression check.** 4.2: units **773** (was 767; +6 from this file), 0F/0E, 4 skips · spec 145, 0F/0E · functional 88, 0F/0E. 5.0 units: 773, **1F/2E** — identical to the Phase 3 baseline, so nothing here moved the ten.

### B — The ten Rails 5 failures (work item 4.0) ✅

**Result: both bundles fully green.** All ten resolved, plus one intermittent that was not on the list. Criterion 13 is met.

| Suite | Entry (Phase 3) | Exit |
|---|---|---|
| 4.2 unit / spec / functional / orphan | 1007, 0F/0E | **1021, 0F/0E** |
| 4.2 cucumber | 154 / 154 | **154 / 154** |
| 5.0 unit | 1F / 2E | **780, 0F / 0E** |
| 5.0 spec | 0F / 0E | 145, 0F / 0E |
| 5.0 functional | 0F / 3E | **89, 0F / 0E** |
| 5.0 cucumber | 150 / 154 | **154 / 154** |
| line / branch coverage (4.2) | 78.37% / 70.83% | **78.44% / 70.88%** |

`rake ci:test` exits **0** on 4.2 with coverage gating on. `test/dummy/db/schema.rb` unchanged throughout.

**The headline finding: only one of the four root causes was actually a Rails 5 incompatibility.** Three were live defects on the shipping 4.2 bundle that the 5.0 suite happened to expose — which is the thesis of this phase, arriving from an unexpected direction.

#### B.1 — The cluster (7 of 10) ✅ — one fix

Root cause at [`versioning.rb:167`](../../lib/cms/behaviors/versioning.rb#L167). `after_save :touch_self_and_ancestors` touches `self`; callers legitimately hold a parent loaded before a child update bumped its `lock_version`. Measured on the PageComponent path: **in-memory 3, database 4**.

`create_content_table` gives every versioned content table a `lock_version` ([schema_statements.rb:33](../../lib/cms/extensions/active_record/connection_adapters/abstract/schema_statements.rb#L33)), so optimistic locking is on for all of them.

| | 4.2 | 5.0 |
|---|---|---|
| `touch`'s WHERE | `id` only | `id` **and** `lock_version` |
| Zero rows matched | returns false | **raises `StaleObjectError`** |

4.2 incremented from the *stale* value, writing `lock_version = 4` over a row already at 4 — **optimistic locking has been silently defeated on 4.2 all along.** Rails 5 exposed it rather than caused it.

Fixed by re-reading the locking column before the touch (not `#reload` — the record is mid-save and holds pending changes). `Section`'s duplicate of the method needed nothing: `cms_sections` has no `lock_version`.

**This one fix cleared all seven**, confirming §6's "symptom of a symptom" reading: the update now succeeds, so the controller never re-renders the form, so the missing partial is never reached.

Characterization in [`versioning_locking_test.rb`](../../test/unit/behaviors/versioning_locking_test.rb), 7 tests. With the fix disabled, **5.0 goes red and 4.2 stays green** — which is what makes it characterization rather than regression. Its last test pins the defect [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it) left alone, and says so in its own failure message.

#### B.2 — The missing partial → **closed in [stage G](#g--the-versioning-call-chain-tests-work-item-46-and-b2)**

**Not fixed here, and no longer reachable from here.** [`_main_form.html.erb:2`](../../app/views/cms/pages/_main_form.html.erb#L2) rendered `cms/shared/version_conflict_error`, which does not exist — the file is under `cms/application/`. B.1 removed the only path that reached it. **It remained a latent 4.2 bug**, so the fix and its characterization test were carried to stage G, where the versioning tests live. Stage G also found a **second** broken path in the same file that this diagnosis missed.

#### B.3 — The truthiness class ✅ — and [1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug) was wrong about the cause

⚠️ **Correction.** 1.9 called this a Rails 5 difference. It is not. Probed with an explicit `task_ids => ""` on both bundles:

```
PROBE 4.2.11.3: PG::InvalidTextRepresentation: invalid input syntax for type integer: ""
PROBE 5.0.7.2:  PG::InvalidTextRepresentation: invalid input syntax for type integer: ""
```

**Identical.** A real request with `?task_ids=` has been a 500 on the shipping 4.2 bundle all along. The only Rails 5 difference is that the *test harness* serializes `params: {x => nil}` as `nil` on 4.2 and `""` on 5.0 — so 5.0's run happened to exercise a bug 4.2's run walked past.

That removes [D5](#d5--how-far-to-take-the-truthiness-audit)'s escalation concern entirely: there is no 4.2 behaviour to preserve, because 4.2 is already broken in exactly the same way.

**Six sites fixed** (`.present?`), all of which put a blank straight into a finder or an integer column: `attachments_controller.rb:13`, `content_block_controller.rb:128`, `toolbar_controller.rb:14`, `tasks_controller.rb:22`, `pages_controller.rb:74`, `sections_controller.rb:68`.

**Three left alone and written down**, because they degrade rather than crash and changing them is a product decision, not an upgrade one:

| Site | Blank behaviour |
|---|---|
| `content_block_controller.rb:219` | `params[model_form_name]` — nested hash, not a scalar |
| `inline_content_controller.rb:20` | `"".to_sym` → `:""` → empty connector list. Degrades silently |
| `users_controller.rb:15` | ⚠️ `?show_expired=` **shows expired users on both bundles.** A silent wrong result, one word from being fixed — but it changes what a URL does, so it needs an owner |

#### B.4 — `test_publish_on_save` ✅ — this was **B7**, hidden by a bare rescue

Not a `save!` interaction as the plan guessed. [`publishing.rb:146`](../../lib/cms/behaviors/publishing.rb#L146) called `self.class.quote_value(id)` with one argument; `quote_value` is `(value, column)` on 4.2 and lost its second parameter by 5.0. So on **4.2 it raised `ArgumentError`** — and `publish` ([publishing.rb:101](../../lib/cms/behaviors/publishing.rb#L101)) rescues `Exception`, logs, and returns false. **Publishing a non-versioned record silently did nothing on the shipping bundle.**

The test's assertion had been inverted to agree with it in `c6994b96` (2017, *"All tests working"*). Rails 5 made the call work, the record published, and the test failed.

Fixed to `connection.quote(id)` (one argument on both) and the assertion restored, with the history recorded at the test so nobody inverts it back. **No model in the engine is publishable-but-not-versioned**, so this branch is unreachable here and reachable only for a downstream project defining one — which is why it is a fix and not a deletion. This retires Tier B's **B7**.

#### B.5 — `portlets_with_params` ✅ — this was **B9**

Not "renders the page layout" as recorded. The portlet rendered its own *not-found* branch — `Fail. param[:category_id] is missing.` — inside the editor iframe. Only the logged-in scenario failed, and the only thing it does differently is `visit_content_iframe`.

[`content_controller.rb:76`](../../app/controllers/cms/content_controller.rb#L76) builds that iframe URL by passing `params.except(...)` into `url_for`. Measured:

| | URL produced |
|---|---|
| 4.2 | `/page_2?category_id=42` |
| 5.0 | `/page_2?params%5Bcategory_id%5D=42` |

On 4.2 `ActionController::Parameters` subclasses `HashWithIndifferentAccess`, so `url_for` flattens it. On 5.0 it is not a Hash, so it becomes one opaque value — **every parameter silently vanishes from the edit-mode iframe URL.** Fixed with `.to_unsafe_h`, which exists on both and produces identical URLs. This is Tier B's **B9** at the site the analysis said CI would catch; it did.

#### B.6 — `PortletTest#test_.blacklist` ✅ — not one of the ten

Phase 3 recorded this as resolved-but-flaky. It is worse than that: at **the same seed** it failed on 5.0 and passed on 4.2, and across seeds it moved on both. `Cms::Portlet.blacklist` memoizes into `@blacklist` ([portlet.rb:103](../../app/models/cms/portlet.rb#L103)) and `.types` calls it, so if anything touched either earlier in the run the test's stub never applied and it asserted against real configuration.

Cleared on both sides of the test — the `ensure` half also stops the stubbed value leaking into every test that follows. Verified stable across seeds 1, 2, 3 and 7.

**A job that goes green on a lucky ordering is not green**, so this had to close before criterion 13 could be claimed.

- [x] All ten resolved; `next-rails` green
- [x] Each has a test that passes on the **`Gemfile`** bundle (criterion 14)
- [x] 4.2 still green — 1021 tests, 0F/0E, cucumber 154/154, `ci:test` exit 0
- [x] Coverage up on both axes, measured on a cleared resultset
- [x] `test/dummy/db/schema.rb` unchanged
- [x] B.2's partial fix and its characterization test — carried to and **closed in [stage G](#g--the-versioning-call-chain-tests-work-item-46-and-b2)**

### C — The eager-load test (work item 4.2) ✅ written here, enabled in stage F

**Written, passing on both bundles, and deliberately kept out of the gated suite until stage F.** [`test/unit/eager_load_test.rb`](../../test/unit/eager_load_test.rb), 4 tests. Criterion 5 was **not** met at the end of this stage, knowingly — it was met in [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44), where the deferral was resolved by re-baselining rather than by skipping. The rest of this section is the state **as of stage C**; read it with that date on it.

#### What it found

`Rails.application.eager_load!` succeeds on both bundles — no explosion, contrary to the stage's own expectation. The value turned out to be in the second test, which checks the contract Zeitwerk will enforce at 6.0: **a file at `<root>/a/b_c.rb` must define `A::BC`.** Swept 128 files across 6 engine roots. **One violation:**

| Path | Constant the path implies | Constant the file defines |
|---|---|---|
| `app/portlets/helpers/cms/list_portlet_helper.rb` | `Helpers::Cms::ListPortletHelper` | bare top-level `ListPortletHelper` |

Missing **both** the `Helpers::` and the `Cms::` segment; `Cms::ListPortletHelper` does not resolve either. It works today only because portlet helpers are found by Rails' helper lookup at render time, never by constant autoloading. Zeitwerk validates the mapping at boot regardless of how the constant is reached, so this is a hard 6.0 boot failure.

Recorded in `KNOWN_ZEITWERK_MISMATCHES` rather than fixed — naming is 6.0 work. The allowlist is the inventory, and the test fails on any **new** violation, so the list cannot quietly grow. Proven in both directions: a planted bad file fails it, and removing a still-broken entry from the list fails it too.

#### `engine.rb:112-116` is almost entirely redundant

[`TEST_COVERAGE_ANALYSIS.md` §3.6](../../TEST_COVERAGE_ANALYSIS.md) calls this block the single biggest concentration of upgrade work. Measured, it is nine pushes of which **at most one does anything**:

| Path | Status |
|---|---|
| `<engine>/vendor` | exists, **contains no `.rb` files** |
| `<engine>/app/mailers` | **directory does not exist** |
| `<engine>/app/{helpers,controllers,models,portlets}` | duplicates of the engine's own `eager_load_paths` |
| `<host>/app/portlets` | Rails already globs `app/*` into the host's paths |
| `<host>/app/presenters` | same, when it exists |
| `<host>/app/portlets/helpers` | nested one level deeper than the `app/*` glob reaches — the only additive entry, and even it is covered for *loading* because eager loading walks roots recursively |

That materially shrinks the 6.0 estimate: the Zeitwerk work here is one misnamed file and a block that can mostly be deleted, not nine paths to re-home.

#### Why it was deferred

The test passes in under a second. The problem is what `eager_load!` does to the coverage denominator — it loads **seven files no suite otherwise touches**, adding 32 unexercised branches:

| | without | with |
|---|---|---|
| branch numerator | 1013 | **1013** — identical |
| branch denominator | 1429 | 1461 |
| branch coverage | 70.89% | **69.34%** — under the 70.83% gate |
| line coverage | 78.44% | 82.49% |

The seven: `form_entries_controller` (12 branches, public form submission), `form_fields_controller` (4), `page_route_options_controller` (4), `toolbar_controller` (4), `attachments_input` (4), `page_components_controller` (2), `portlet_controller` (2).

**Nothing got less tested.** The old baseline was computed over a universe that silently excluded seven untested controllers, two of which criterion 7 already names. So the new number is more honest — but acting on it means lowering a quality gate on the strength of a test written minutes earlier, and **the decision was taken to hold the gate instead**.

> **Seven here, six in [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44) and in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake).** Not a contradiction — the two counts are dated. `form_fields_controller` (4 branches) is the seventh, and stage F wrote tests for it under criterion 7, so by the time the threshold was set it was no longer a file that *only* `eager_load!` reaches. 32 branches − 4 = the 28 recorded there.

The test is therefore skipped unless `EAGER_LOAD_TEST=1`, with the reasoning at the top of the file and in the skip message (Phase 0 criterion 5 wants a stated reason, and this is one). Stage F adds tests for both Forms controllers; re-measure then:

- **clears 70.83%** → delete the `setup` block, the test joins the suite, criterion 5 is met
- **still short** → the baseline decision returns, from the much better position of having the phase's other work already done

- [x] `Rails.application.eager_load!` runs clean on both bundles
- [x] The Zeitwerk path→constant contract is asserted, and the guard proven in both directions
- [x] The 6.0 inventory is written down — one misnamed file, and a mostly-redundant autoload block
- [x] ⚠️ **Criterion 5 was unmet at the close of this stage** — the test did not yet run in the default suite. Resolved in [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44): the skip block was removed, `COVERAGE_MINIMUM_BRANCH` was re-baselined to 70.49%, and criterion 5 is met

### D — `belongs_to`: close the gap (work item 4.1) ✅

Small, as [1.1](#11-work-item-41-is-substantially-already-built) predicted. Phase 3's audit test was **adopted rather than replaced**; it went from 9 tests to 11.

- [x] **The `dynamic_attributes` assertion** — the one genuinely missing test ([1.4](#14-one-declaration-has-no-assertion-and-it-is-a-dynamic-one))
- [x] **The count tripwire** ([D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite)) — `24 literal + 3 injected + 2 dynamic = 29`, so criterion 4's stated check is now literally true
- [x] **The header comment rewritten** — it said "Phase 4 owns the permanent version of this"; it now *is* that version, and carries the [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant) reasoning so the flag is not reintroduced at 5.1
- [x] **`belongs_to_required_by_default` set nowhere** — `grep` returns only comments

Both new assertions proven to guard: removing `required: false` from the dynamic declaration fails with the affected portlets named, and adding an audit entry trips the count.

#### The dynamic declaration multiplies, which is why it mattered

[`dynamic_attributes.rb:171`](../../lib/cms/behaviors/dynamic_attributes.rb#L171) is reached from `Cms::Portlet.inherited` ([portlet.rb:37](../../app/models/cms/portlet.rb#L37)), so it runs **once per portlet subclass** — and every run does `class_eval { belongs_to base_class, … }` against the *same* `CmsPortletAttribute`. That class therefore accumulates one `belongs_to` per portlet type: four in this repo, plus one for every portlet a consuming project defines.

A missing `required: false` there would not fail on one model. It would fail on whichever portlet the downstream app happened to write, on the day it moved to `load_defaults 5.0` — which is exactly the failure mode this phase exists to prevent and the one `grep` cannot see. Asserted over the reflections rather than by name, because the names derive from subclasses that do not exist here.

**4.1 is closed.** Criteria 3 and 4 are met, 3 by [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant)'s amendment rather than as written.

### E — `create_content_table` option matrix (work item 4.3) ✅

Extended [`schema_statements_test.rb`](../../test/unit/schema_statements_test.rb) from 6 tests to **13**, as [1.7](#17-b3--criterion-6-is-partly-done) scoped it. Criterion 6 met.

The DSL takes exactly two options — `:versioned` and `:name`, both defaulting true — so "every option combination" is a 2×2 matrix, now enumerated in full. Each case asserts the **complete column set** on both tables rather than one column's presence, because the failure worth catching is a column quietly appearing or disappearing.

| Case | Content table | `_versions` table |
|---|---|---|
| versioned + named (default) | base + `version`, `lock_version`, `name` | base + `original_record_id`, `version`, `version_comment`, `name` |
| versioned + unnamed | base + `version`, `lock_version` | base + `original_record_id`, `version`, `version_comment` |
| non-versioned + named | base + `name` | **not created** |
| non-versioned + unnamed | base only | **not created** |

Three further tests cover what the matrix alone would miss:

- **The two asymmetries.** `lock_version` is on the content table only; `version_comment` on the versions table only. Easy to break and easy to miss, because the two tables otherwise carry nearly the same columns.
- **The caller's block reaches both tables.** A versioned content type has to carry its own columns in its history as well as its current row, or reverts and version comparisons silently lose data.
- **Unrecognised options are forwarded to `create_table`.** This is the line B3 actually flags — `create_table table_name, options` is positional today and becomes an `ArgumentError` if options ever turn into keyword arguments. Asserted on the resulting table rather than on the call, so it survives whichever way Rails spells it.

**Proven to guard**, with one instructive miss. Removing `lock_version` from the DSL fails 4 tests. Adding `version_comment` to the content table appeared *not* to fail anything — until it turned out my `sed` had silently not matched (the indentation was 10 spaces, not 12). Applied properly it fails 6 tests, including the asymmetry assertion by name. **The false negative was in the check, not the tests** — worth recording, because a sabotage that silently does nothing looks exactly like a test that does nothing.

### F — `Parameters` on the four uncovered sites (work item 4.4) ✅

Criteria 7 and 5 both met. **Functional tests went from 89 to 122**, and the stage turned up three live defects plus an eleventh B9 site.

#### The four sites

| Site | Test | What it asserts |
|---|---|---|
| `form_fields_controller.rb:16` | new file, 5 tests | `.delete` does two jobs — returns the id *and* removes the key. Asserted separately, so a regression in either half is attributable |
| `forms_controller.rb:33` | new file, 5 tests | `:new_entry` is stripped before assignment, plus the sibling callback at `:26` that **assigns into** `params[:form]` |
| `pages_controller.rb:124-128` | [`parameters_authorization_test.rb`](../../test/functional/cms/parameters_authorization_test.rb) | `:hidden`/`:archived`/`:visibility` stripped for a non-publisher, **and** honoured for a publisher |
| `sections_controller.rb:42` | same file | `group_ids` stripped for a non-administrator, **and** honoured for an administrator |

Both authorization sites assert **both directions**, deliberately. A test that only checks the restricted user passes if the strip runs unconditionally and breaks the feature for everyone; one that only checks the privileged user passes if the strip never runs. Sabotaged both: disabling either control fails with *"an authorization control has failed OPEN"*.

Coverage, criterion 7's actual check: `form_fields_controller` **0% → 42.6%**, `forms_controller` **0% → 72.7%**.

#### An eleventh B9 site, and a 5.1 breakage

The analysis listed ten `Parameters` sites. Instantiating a 0%-coverage controller surfaced another: [`content_block_controller.rb:275`](../../app/controllers/cms/content_block_controller.rb#L275) does `defaults.merge(model_params)` where `defaults` is a plain Hash. `Hash#merge` coerces via `to_hash`, which 5.0 deprecates and **5.1 changes to enforce parameter filtering** — at which point content blocks would silently start losing unpermitted fields on save.

Fixed with `.to_unsafe_h`, which is explicit about what the line already did (`Hash#merge` already returned a plain Hash, so the result was never subject to strong-parameter checking) and behaves identically on both bundles.

#### Three live defects, none caused by the upgrade

All three fail identically on both bundles. All three were invisible because nothing ever loaded the controller.

1. **Public form submission returns 500.** `Cms::Form.layout` does not exist — nothing in the engine defines `self.layout` — and [`form_entries_controller.rb:17`](../../app/controllers/cms/form_entries_controller.rb#L17) and `:31` both call it. So every form configured to show confirmation text, and every validation failure, 500s for the visitor. The entry saves first, so no data is lost. **The most serious finding of the phase**: public-facing, and `allow_guests_to [:submit]` means unauthenticated.
2. **The Forms admin UI returns 500.** Same shape: `Cms::Form.path` does not exist either, but [`_form.html.erb:7`](../../app/views/cms/forms/_form.html.erb#L7) renders `f.input :slug, as: :path` and `PathInput` calls `object.class.path`. `is_addressable` is commented out at [`form.rb:5`](../../app/models/cms/form.rb#L5). The same abandoned migration explains the `:form` **factory**, which set a `slug` that does not exist on `cms_forms` and had never been called by anything — 0% coverage extended to the test infrastructure.
3. **`Cms::ToolbarController` is vestigial.** Routed, and the action runs, but there is no `app/views/cms/toolbar/index` template and the layout it declares (`cms/toolbar`) does not exist either. `GET /toolbar` can never render. Only the directory's `_new_pages_menu` partial is still used, from `_main_menu.html.erb:56`.

⚠️ **A correction to stage B this forces.** `toolbar_controller.rb:14` was one of the nine truthiness guards fixed in [B.3](#b--the-ten-rails-5-failures-work-item-40) — so that one was a fix to unreachable code. Still the right change (same defect, shipped file), but the B.3 count should not be read as nine live paths.

All three are **characterized, not fixed.** Each repair is a product decision — which layout should a confirmation render in, are Forms addressable, should a routed controller be deleted — not an upgrade one. Each test pins current behaviour and fails when someone fixes it, saying so in its own failure message.

#### The coverage gate: re-baselined, and why

This is the part worth reading before anyone "restores" the old number.

[Stage C](#c--the-eager-load-test-work-item-42--written-here-enabled-in-stage-f) held the eager-load test out of the suite because `eager_load!` loads six files nothing else touches, adding **28 unexercised branches** to the denominator and dropping branch coverage below the 70.83% gate. The decision taken then was to hold the gate and revisit here.

Revisited, with tests written to try to close it honestly:

| | branch coverage |
|---|---|
| Stage C, test deferred | 70.89% (gate met, six controllers invisible) |
| Stage F entry, test enabled | 69.54% |
| after `form_entries_controller` (10 tests) | 70.09% |
| after toolbar / portlet / page_components (8 tests) | **70.50%** |
| gate | 70.83% |

**Five branches short, and the remaining ones are not worth having:**

- `page_route_options_controller` (4 branches) — **zero routes.** Unreachable dead code, and its `load_page_route` never assigns `@page_route`, so it could not work if called.
- `attachments_input` (1 of 4) — needs a model with two multiple-attachment definitions. None exists; one would have to be invented for the test.
- `portlet_controller` else-branch (1) — needs a portlet class defined at global scope purely for the test.

Writing those is precisely what the phase document rules out: *"Writing tests to raise a percentage is the wrong objective here."*

**So the baseline was re-measured: `COVERAGE_MINIMUM_BRANCH` 70.83 → 70.49.** The reasoning, and this list, is recorded beside the threshold in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake) and in [`.simplecov`](../../.simplecov), because a future reader will otherwise see a lowered gate and assume a regression.

**Nothing became less tested.** The branch numerator never fell. The old 70.83% was measured over a universe that silently excluded six untested controllers; 70.49% measures the real one. Line coverage moved the other way for the same reason — **78.44% → 83.54%**.

The return on the exercise was not the percentage. It was `form_entries_controller`: 108 lines, 0%, public form submission, on Phase 5's manual-verification list — now 10 tests, and the reason we know the confirmation path has been 500ing.

- [x] Both Forms controllers off 0% (criterion 7)
- [x] All four `Parameters` sites tested, both directions on the authorization pair
- [x] Eager-load test now runs in the default suite (criterion 5)
- [x] `ci:test` exits 0 on 4.2; both bundles green; `schema.rb` unchanged
- [x] Skips back to 4 — the four deferred eager-load skips are gone

### G — The versioning call-chain tests (work item 4.6) and B.2 ✅

Two items: B6's three questions, and the partial fix [B.2](#b2--the-missing-partial--closed-in-stage-g) deferred out of stage B.

[`versioning_call_chain_test.rb`](../../test/unit/behaviors/versioning_call_chain_test.rb), **14 tests**, and [`version_conflict_test.rb`](../../test/functional/cms/version_conflict_test.rb), **5 tests**. Green on both bundles.

#### The audit, answered (criterion 10)

[1.8](#18-b6s-three-questions-all-answer-no--the-audit-is-already-done) established by grep that none of the three questions had an assertion anywhere in [`versioning_test.rb`](../../test/unit/behaviors/versioning_test.rb). B6 budgeted a day of reading to reach that; the grep took a minute. What the budget was really for is the half the audit cannot do — running the questions and finding out what the answers are:

| | asserted before? | actual behaviour |
|---|---|---|
| A failed validation produces no new version row | no | **correct** — now pinned, 4 tests |
| `version_comment` reflects *this* save's changes | no | **correct for an ordinary load, wrong on the CMS edit path** — see below |
| A rolled-back transaction leaves no orphan version row | no | **correct** — now pinned, 3 tests |

Two of three were right all along and simply unguarded. That is worth stating without dressing it up: most of this file's value is a tripwire under behaviour that already works, not a defect count. `versioning.rb` does not override one method, it replaces the save call chain — `create_or_update` intercepts every update to save a *version row* instead of the record — and both its signatures were rewritten in Phases 1 and 2. Behaviour that depends on where a hook sits relative to that chain can move at any hop with nothing to catch it.

#### Q2's answer is "no", and the author knew

[`versioning.rb:258-259`](../../lib/cms/behaviors/versioning.rb#L258) carries a comment from the original author:

```ruby
# This doesn't always seem to properly be applied, or is applying for
# ALL fields, not just the changed ones.
```

It is right, and the cause is one line. [`build_object_from_version`](../../lib/cms/behaviors/versioning.rb#L21) copies every versioned column onto a fresh object and ends with:

```ruby
# Last but not least, clear the changed attributes
clear_changes_information          # <- versioning.rb:39
```

That is an implicit `self.`, and `self` there is the **`Version` record**, not the `obj` being built and returned. The object that needed clearing never gets it. So everything `as_of_version` and `as_of_draft_version` return arrives with every non-nil versioned column marked dirty, plus `id`, `created_at` and `updated_at`, which are not versioned columns at all.

That is the admin edit path, not an obscure one:

```
pages_controller.rb:137-140   load_draft_page -> @page.as_of_draft_version
pages_controller.rb:46        @page.update(page_params)
```

Change a page's name through the CMS and the version row is commented `Changed content, created_at, id, name, published, updated_at`. The history is intact and useless, which is why it has never been reported.

There is a second consequence. [`different_from_last_draft?`](../../lib/cms/behaviors/versioning.rb#L430) short-circuits on `self.changed?`, so it is unconditionally true for these objects and the "unchanged record, skip the save" branch at [versioning.rb:297](../../lib/cms/behaviors/versioning.rb#L297) **never fires on the UI path**. Saving a page you have not edited still writes a version row. The existing test `"Saving a block without changing any attributes should skip after_save callbacks"` passes only because it uses a freshly-created object rather than a draft one — a good example of a test that measures the right thing on the wrong object.

**Not fixed.** `obj.clear_changes_information` is a one-word change to the comment text, but it also switches that skip-save branch on for the engine's busiest write path, where it has never run in any released version. That is a behaviour change to 4.2, which is the line [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it) drew for optimistic locking, drawn here for the same reason. Three tests pin the current behaviour, including the exact comment string, and fail when it is repaired.

Identical on both bundles. **Not caused by the upgrade.**

#### B.2 — and a second broken path in the same file

[Stage B](#b2--the-missing-partial--closed-in-stage-g) named one broken partial reference. There were two:

| [`_main_form.html.erb`](../../app/views/cms/pages/_main_form.html.erb) | rendered | exists at |
|---|---|---|
| line 2 | `cms/shared/version_conflict_error` | `cms/application/_version_conflict_error.html.erb` |
| line 23 | `cms/shared/version_conflict_diff` | `cms/application/_version_conflict_diff.html.erb` |

Both now point at `cms/application/`. Fixing only the one stage B named would have moved the failure down eighteen lines and looked like a fix — the reason the test asserts both partials separately, and each sabotage was run on its own to prove it.

**This branch is unreachable through ordinary use.** [`pages_controller.rb:52`](../../app/controllers/cms/pages_controller.rb#L52) enters it only on `StaleObjectError`, and versioning's `create_or_update` never issues an UPDATE against the page row — it saves a version row instead — so the parent's `lock_version` is never checked on the write path. The one place that did check it was the after_save touch, on 5.0 only, and B.1's `sync_locking_column_before_touch` stopped that. So the trigger in the test is stubbed: `save` raises the error the controller declares it rescues. Everything after that is real — the rescue, the reload, and the full render through `edit.html.erb` → `_form` → `_main_form` → both partials. **It is the render that was broken and the render that is tested.**

A fifth test asserts the ordinary edit screen renders *neither* partial, so the other four cannot pass against a form that has simply stopped showing conflicts.

#### Sabotage

| change | result |
|---|---|
| `versions.build` → `versions.create` | 13 of 14 red |
| `changes.keys` → `attributes.keys` in `default_version_comment` | 4 red, all Q2 |
| `cms/application/version_conflict_error` → `cms/shared/...` | 4 of 5 red |
| `cms/application/version_conflict_diff` → `cms/shared/...` (alone) | 3 of 5 red |

No cheap sabotage was found for Q3 — defeating it means taking the version INSERT off the caller's connection, and every one-line way to do that also breaks the suite wholesale. Those three tests instead assert *inside* the transaction that the row and the `latest_version` column really did change before asserting they are gone afterwards, so they cannot pass vacuously. Stated rather than skipped, because [stage E](#e--create_content_table-option-matrix-work-item-43) is where we learned that a sabotage which silently does nothing is indistinguishable from a test that does nothing.

#### A note on the suite count

14 new tests move the unit suite 793 → **808**. The extra one is [`namespaces_test.rb`](../../test/unit/models/namespaces_test.rb), which generates one test per constant under `Cms` at load time; a test class declared in that namespace therefore mints a no-op test for itself. Every `Cms::`-namespaced test class in the repo already does this. Noted so the arithmetic is not mistaken for a miscount.

- [x] A failed validation produces **no** new version row — 4 tests, including Page's raw-SQL `latest_version`
- [x] `version_comment` reflects the changes from *this* save — 4 tests, plus 3 characterizing the path where it does not
- [x] A rolled-back transaction leaves **no** orphan version row — 3 tests, including the raw-SQL column
- [x] The three answers written down (criterion 10) — here and in the test file's header
- [x] B.2's two partial paths fixed and covered by 5 tests, each sabotaged separately
- [x] Both bundles green; `ci:test` exit 0; `schema.rb` unchanged; branch coverage holds at 70.49%

### H — The rest of Tier B (work items 4.5, 4.7) ✅

Three new files, **28 tests**, green on both bundles:

| file | item | tests |
|---|---|---|
| [`publishing_sql_test.rb`](../../test/unit/behaviors/publishing_sql_test.rb) | B7 | 8 |
| [`soft_deleting_test.rb`](../../test/unit/behaviors/soft_deleting_test.rb) | B8 | 10 |
| [`dynamic_attributes_chain_test.rb`](../../test/unit/behaviors/dynamic_attributes_chain_test.rb) | B2 | 10 |

#### This plan dropped an item, and the phase document caught it

The stage H checklist below listed 4.5, B7, B8 and "B4 out of scope". Work item 4.7 in [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md) has **three** bullets, and **B2 — the `dynamic_attributes` attribute chain — is not one of the four.** It was lost when this plan was written, not deliberately scoped out.

It was picked up by checking the stage against the phase document rather than against this file, which is the whole reason [the README](README.md) describes the phase file as the contract and the plan as an approach to it. Had it gone the other way the item would have vanished with no record. **B2 turned out to be the most productive of the three.**

#### B7 — `publish!` writes with hand-built SQL, so assert the row

The point of this item is one distinction: `publish!` sets `self.published = true` in memory at [publishing.rb:169](../../lib/cms/behaviors/publishing.rb#L169) **whatever the SQL did**, so an assertion against the object under test passes against a completely broken write. Every test here reads the column back with `SELECT`.

That is not hypothetical — it is [B.4](#b4--test_publish_on_save---this-was-b7-hidden-by-a-bare-rescue) restated. `publish` swallows `Exception`, so the ArgumentError from `quote_value` returned `false` for years and the test was edited to agree with it.

Covered: the draft's values reaching the live row; the version row *and* the live row both being marked; no new version row (documented at publishing.rb:97-98, never asserted); a no-op publish returning false and not touching `updated_at`; the non-versioned branch flipping the column; and that branch's interpolated `WHERE` touching **only** the row it was given.

Deliberately **not** asserted: the API shape. [publishing.rb:161](../../lib/cms/behaviors/publishing.rb#L161) still uses the two-argument `connection.quote(value, column)`, deprecated at 5.0 and removed at 5.1. These tests assert the resulting row, so they survive that removal and fail only if the fix for it is wrong.

One characterization: **`publish` returns false rather than raising a programming error.** `rescue Exception` catches NoMethodError and ArgumentError alongside real failures. Not fixed — narrowing it changes every save of every content type on 4.2 as much as 5.0, which is [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it)'s line.

#### B8 — the three things about `soft_deleting` that are not ActiveRecord

`soft_deleting.rb` is not untested: [`content_block_test.rb`](../../test/unit/lib/content_block_test.rb) already asserts that destroy marks rather than removes, that `find` raises, that `count` excludes and `with_deleted` includes. Repeating those would have added lines and no defence. The gaps were the parts that are not ordinary ActiveRecord:

1. **The default scope might not be there.** [soft_deleting.rb:30-35](../../lib/cms/behaviors/soft_deleting.rb#L30) installs it inside `rescue StandardError`, because it can run before the table exists. A failure for any *other* reason is then indistinguishable from success, logged at debug level. Now asserted directly.
2. **Composition.** Every existing assertion is against a bare `Model.count` or `Model.find`. A default scope that survives those and is dropped by a `where` chain would pass all of them. Now asserted in both chaining orders, and with `order`/`limit`.
3. **`delete_all` does not delete**, and `delete_all!` — which does — exists only because of an `alias_method` taken three lines before the `extend ClassMethods` that would otherwise shadow it. Swap those two lines and a hard delete silently stops happening. That ordering is now a test.

Plus one characterization: **`Model.exists?` with no arguments raises ArgumentError.** [soft_deleting.rb:56](../../lib/cms/behaviors/soft_deleting.rb#L56) redefines a Rails method whose argument is optional with one that is required, on `Cms::Page`, `Cms::Portlet`, `Cms::Attachment`, `Cms::DynamicView` and every content block. Not reachable from engine code — no no-argument call exists — and the relation form is untouched, which is why `.any?` and `.present?` still work and why nothing has tripped over it. Not fixed: the override also answers with `count > 0` rather than Rails' `LIMIT 1`, so giving the parameter a default quietly commits every caller to a full count.

#### The `or` clause cannot be satisfied in this phase

Work item 4.7 asks that the default scope "composes correctly with `where` **and `or`**". `ActiveRecord::Relation#or` **arrives in Rails 5.0** — `Cms::HtmlBlock.all.respond_to?(:or)` is `false` on the `Gemfile` bundle. A characterization test must pass on both bundles ([criterion 11](#7-exit-criteria-traceability)), so this half cannot be written here; a version-guarded test would silently assert nothing on 4.2, which is the shape this phase exists to remove.

Measured rather than merely deferred. On 5.0 the default scope **does** distribute correctly across both sides of an `or`:

```sql
WHERE ("cms_html_blocks"."deleted" = 'f' AND "name" = 'OrA'
    OR "cms_html_blocks"."deleted" = 'f' AND "name" = 'OrB')
```

Handed to Phase 5 with that answer attached, where `or` is available and the test is one line.

#### B2 — the item this plan lost, and the three defects in it

`dynamic_attributes.rb` is 387 lines against 73 lines of test, the worst ratio in the engine, and what it does is replace ActiveRecord's attribute chain by `alias_method` on every class built by `Cms::Portlet.inherited`. Three disagreements between the aliases and ActiveRecord, all identical on both bundles, **none caused by the upgrade**:

1. **`read_attribute` and `write_attribute` are private on these models, and calling them returns `nil`.** An explicit-receiver call to a private method raises NoMethodError; [`method_missing_with_dynamic_attributes`](../../lib/cms/behaviors/dynamic_attributes.rb#L327) rescues NoMethodError and treats the method name as a dynamic attribute name. So `record.read_attribute('price')` is answered as "the dynamic attribute called `read_attribute`" — `nil`, no error — while `record['price']` is correct. Nothing in the engine calls either with an explicit receiver, which is why it has never surfaced.
2. **`_read_attribute` is not aliased.** B2 asks whether both resolve dynamic attributes. Only the wrapper was aliased; the underscore form that ActiveRecord uses internally was not. Benign today, and the direction of travel is against it — each release moves more internals onto it.
3. **`nonversioned_class` raises `FrozenError` in the only case it exists for.** [dynamic_attributes.rb:376](../../lib/cms/behaviors/dynamic_attributes.rb#L376) does `base_class = kls.name` then `base_class.sub!(...)` — `sub!` mutates the string `Class#name` returned, which Ruby froze. The `::Version` branch is the entire reason the method exists and it cannot execute. Unreachable in this engine (portlets declare `versioned: false`); immediate for a downstream project combining `has_dynamic_attributes` with `is_versioned`. Before the string was frozen this would have **renamed the class in place**.

And a fourth, of a different kind: `respond_to?(:price)` is `false` for an attribute `record.price` answers, because `respond_to_missing?` is not implemented — so `try(:price)` returns `nil` for an attribute that is right there. Not fixed: a `respond_to_missing?` that is correct here would have to return true for *every* name, since dynamic attributes have no declared set.

#### A correction, caught by sabotage

The first draft of the B2 write-up blamed the `private` at [dynamic_attributes.rb:193](../../lib/cms/behaviors/dynamic_attributes.rb#L193), which sits directly above the aliases and is what any reader would reach for. Removing it changes nothing and the tests stay green.

`alias_method` **ignores the current default visibility** and copies the visibility of the method being aliased:

```ruby
module M; private; def secret; end; end
class C; include M; alias_method :pub, :secret; end
C.new.respond_to?(:pub)   # => false
```

The aliases are private because their targets are: `read_attribute_with_dynamic_attributes` is defined after the module-level `private` on **line 261**. Removing *that* turns the tests red. Line 193 is dead code that reads as the cause — recorded in the test file, because the next person will make the same guess.

#### Sabotage

Eleven, each verified to have taken effect before its result was believed:

| change | result |
|---|---|
| `delete_all` override → a real delete | 1 red |
| alias/`extend` order swapped in `uses_soft_delete` | 1 red |
| `default_scope` removed | 4 red |
| `exists?` given a default argument | 1 red |
| ~~`destroy` hard-deletes (non-publishable branch)~~ | **0 red — the sabotage was in a branch `Cms::HtmlBlock` does not take** |
| `destroy` hard-deletes (publishable branch) | 2 red, 1 error |
| `update_column` loop dropped from `publish!` | 2 red |
| `WHERE` dropped from the hand-built UPDATE | 1 red |
| `rescue Exception` narrowed in `publish` | 1 error |
| draft version row not marked published | 3 red |
| ~~`private` at dynamic_attributes.rb:193 removed~~ | **0 red — not the cause; see the correction above** |
| `private` at dynamic_attributes.rb:261 removed | 2 red |
| `_read_attribute` aliased as well | 10 errors |
| `write_attribute` alias dropped | 1 error |
| `nonversioned_class` fixed with `.dup` | 1 red |

The two struck rows are the point of running these at all. Both looked like a test failing to catch a regression and were neither: one sabotaged an unreachable branch, the other a line that does nothing. [Stage E](#e--create_content_table-option-matrix-work-item-43) is where this file learned that a sabotage which silently does nothing is indistinguishable from a test that does nothing — twice more here, and the second one corrected a claim that would otherwise have gone into the record wrong.

#### Coverage gate raised

Branch coverage **70.49% → 70.63%**, measured twice on a cleared resultset. `COVERAGE_MINIMUM_BRANCH` moves with it, under the same no-slack policy [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44) set it by — a floor with headroom silently absorbs the first regression. Line coverage 83.60% → **83.67%**.

- [x] **4.5 schema dumper** — folded into [A.3](#a--settle-the-schema-dumper-contradiction-and-fix-b1); nothing separate to do
- [x] **B7 `publishing.rb`** — 8 tests, every assertion read back through `SELECT`
- [x] **B8 `soft_deleting.rb`** — 10 tests, targeting the three non-ActiveRecord parts rather than repeating existing coverage
- [x] **B2 `dynamic_attributes.rb`** — 10 tests. **Missing from this plan; recovered from the phase document**
- [x] **B4 Paperclip is out of scope** — the phase document says validation tests only, no replacement. Not started
- [x] Both bundles green, identical counts; `ci:test` exit 0; `schema.rb` unchanged
- [ ] ⚠️ The `or` half of B8 — **cannot be written on 4.2**; answer measured and handed to Phase 5

### I — Exit, and the Tier C error branches

Two halves: the last outstanding work item, then the exit gate.

#### I.1 — Tier C's three error branches (work item 4.7, final bullet)

**Recovered during the stage-H checkbox audit.** This is the **second** item work item 4.7 lists that never reached this plan, after [B2](#h--the-rest-of-tier-b-work-items-45-47). It is folded in here rather than carried to Phase 5.

The item asks for tests on three branches "worth testing *because* they're error paths nothing exercises". The **fixes** already landed — [Phase 3](phase-3-report.md) converted both `render text:` calls to `render plain:` and `move_to_position`'s `uniq` to `.distinct` in `70b22bdf`. What is still missing is the tests, and all three branches remain at zero coverage. That matters because `render text:` and `Relation#uniq` are both **removed at 5.1**, so the conversions that protect us there are currently unverified.

| # | branch | how to reach it |
|---|---|---|
| 1 | [`content_block_controller.rb:138`](../../app/controllers/cms/content_block_controller.rb#L138) — `render :plain => "Not Implemented", :status => :not_implemented` | `GET versions` on a **non-versioned** content type. Measured: `Cms::Category`, `Cms::Tag`, `Cms::CategoryType` and `Cms::Portlet` are all `versioned? == false` and all have a registered `ContentType` and a `ContentBlockController` subclass. Assert the 501 **and** the body — `render plain:` and `render text:` differ in content type, which is the half a status-only assertion would miss |
| 2 | [`form_fields_controller.rb:43`](../../app/controllers/cms/form_fields_controller.rb#L43) — `render plain: "Fail", status: 500` | `PUT update` with a field that fails validation. Measured: `Cms::FormField` has exactly **one** validator, uniqueness of `:name` scoped to the form — so the way in is a second field whose name collides. Stage F hit this same wall from the `create` side and had to use duplicate labels; reuse that. ⚠️ `update` has **no test at all** today — stage F covered `create` and `new` only |
| 3 | [`section_nodes_controller.rb:80-82`](../../app/controllers/cms/section_nodes_controller.rb#L80) — `nodes_to_update_on_success` | `PUT move_to_position`. **Zero coverage anywhere** — no unit test, no functional test, no feature. See [D8](#d8--the-move_to_position-dedupe-fix-or-characterize) before writing this one |

#### Phase 3 left a hand-off note here, and it was lost too

[`section_nodes_controller.rb:73`](../../app/controllers/cms/section_nodes_controller.rb#L73) carries the only `TODO(Phase 4)` marker in the repository:

> the dedupe below is on the wrong side of the parenthesis. `.distinct` binds to the *second* relation only, so it becomes `SELECT DISTINCT` within that half and does nothing about duplicates *between* the two halves — which is the only kind this method can plausibly produce, since a node can be a sibling in both the previous and the target parent. […] it belongs with the characterization test Phase 4 already owns for `move_to_position`.

That analysis is correct, and it matters for how the conversion is read: `Relation#uniq` on 4.2 is an **alias for `distinct`**, not `Array#uniq`. `.children` returns a Relation, so the original bound the same way. **Phase 3's change was a true rename with no behaviour change** — the defect it describes is older than the upgrade and is not a Phase 3 regression. Worth stating plainly, because a reader finding a dedupe bug directly above a Phase 3 edit will assume otherwise.

#### What I.1 found

Three branches were scoped. All three are now covered, and instrumenting them turned up **three more defects** — none of them caused by the upgrade, all characterized rather than fixed except where noted.

**The dedupe: fixed ([D8](#d8--the-move_to_position-dedupe-fix-or-characterize)).** The consumer was read first, as D8 required. [`Sitemap.prototype.updateValuesOnSuccess`](../../app/assets/javascripts/cms/sitemap.js#L188) is pure assignment — `$row.data('position', position)`, `.html(position)`, `dataset.position = position` — so a repeated triple writes the same values twice and the duplicate was cosmetic. That put it in D8's first branch: the fix is free, and there was nothing left to decide. Before the fix the test failed with every sibling twice on a within-folder move; the `TODO(Phase 4)` marker is gone.

**`move_to_position`'s rescue cannot report the failures most likely to reach it.** [Lines 52-59](../../app/controllers/cms/section_nodes_controller.rb#L52) interpolate `node_to_move.node.name` and `target_parent.node.name` into the failure message, but both locals are assigned by `SectionNode.find` calls *inside* the begin block — so whenever a find is what raised, the handler raises `NoMethodError` on nil and nothing catches it. An unknown id produces an unhandled exception instead of the JSON error the action was written to return. No case was found where the JSON error branch renders at all; even moving a folder into its own descendant returns 200. **Not fixed** — the repair means composing a message without the objects that failed to load, and unlike the dedupe there is no existing intent in the code to read off.

**`form_fields_controller#update` cannot fail.** Three independent facts close every route to the `"Fail"` branch: `:name` is the only validated attribute ([form_field.rb:18](../../app/models/cms/form_field.rb#L18)); it is assigned by `before_validation(on: :create)` so an update never recomputes it ([:14](../../app/models/cms/form_field.rb#L14)); and `permitted_params` is `super - [:name]` so a request cannot set it directly ([:67](../../app/models/cms/form_field.rb#L67)). This took two wrong drafts to establish — a colliding **label** returned 200, then a colliding **name** also returned 200 — which is why all three facts are asserted rather than described. The branch is reached by stubbing, so the `render plain:` conversion still gets verified.

**Why the content type is asserted, not just the status.** `render text:` is removed at 5.1 and Phase 3 converted both sites in `70b22bdf`, but nothing executed either branch afterwards, so the conversions were unverified. `render text:` answers `text/html`; `render plain:` answers `text/plain`. A status-only assertion passes against both and would have proved nothing. Sabotage confirms it: reverting either site to `render text:` turns a test red.

- [x] `versions` on a non-versioned type returns 501 with the expected body **and content type**
- [x] `update` on an invalid form field returns 500 with the expected body — and the valid path still returns JSON
- [x] `move_to_position` moves the node and reports the siblings needing repositioning, on both bundles
- [x] The front-end consumer read before the test was written
- [x] The dedupe defect resolved per [D8](#d8--the-move_to_position-dedupe-fix-or-characterize) — **fixed**, with the `TODO(Phase 4)` marker removed
- [x] Four sabotages, each verified to have taken effect: dedupe back inside the parens (1 red), union halved (1 red), both `render text:` reversions (1 red each)

#### And one the stage did not go looking for

A full `ci:test` run failed on an ordering tie in `sitemap_test.rb`, in a file and a method Phase 4 has never touched. It is written up as [D9](#d9--cmssectionpages-returns-rows-in-arbitrary-order): `Cms::Section#pages` was the only reader on that class that did not order its results. **Fixed on the user's call**, after being raised rather than absorbed.

#### I.2 — Exit

- [ ] Full chain on **both** bundles
- [ ] Coverage on a **cleared** `coverage/.resultset.json`. ⚠️ The branch floor is no longer Phase 3's 70.83% — it was **re-baselined to 70.49% in [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44)** and **raised to 70.63% in [stage H](#h--the-rest-of-tier-b-work-items-45-47)**. `COVERAGE_MINIMUM_BRANCH` is gating, so a drop fails the build rather than the review. Re-baseline **upward** again if I.1 moves it
- [ ] `grep -rn "NextRails" test/ spec/` empty (criterion 11)
- [ ] `git status` clean of `test/dummy/db/schema.rb` — check this before **every** commit in this phase, not just at exit
- [ ] Refresh the [`ci.yml`](../../.github/workflows/ci.yml) `next-rails` comment. ⚠️ **Half done already** — stage B rewrote it from "red and gating" to "GATING, and GREEN", so the item as originally written is stale. What is left is the suite counts inside it, which stage B froze at `780 unit / 145 spec / 89 functional` and are now `837 / 145 / 127`
- [ ] Update [`README.md`](README.md) — Phase 4 status, and Phase 0's criteria 1-2, which unblock the moment this job goes green
- [ ] Confirm criteria 1, 11 and 12 and close the traceability table
- [ ] Write `phase-4-report.md`. It is the record, not this file
- [ ] **Carry B4 forward explicitly.** It is the one work item this phase does not do, and the phase document scopes it to validation tests with no Paperclip replacement. It must land in Phase 5's or Phase 6's document rather than lapsing

---

## 4. Decisions

### D1 — Criterion 3 is replaced by the audit test's invariant

**The problem:** criterion 3 asks for `belongs_to_required_by_default = true` in the test environment. Per [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) it is a no-op in a `setup` block on 5.0, raises `NoMethodError` on 4.2, and the only shape that works — the dummy app's `test.rb` — needs a version guard under `test/`, which criterion 11 forbids.

**Options:** (a) strike it; (b) set it in `test/dummy/config/environments/test.rb` behind a guard and amend criterion 11 to exempt `test/dummy/config/`; (c) replace it with the invariant the audit test already enforces.

**Recommendation: (c).** The criterion's stated purpose is "without this, criterion 4 is meaningless" — it wants criterion 4 to be *falsifiable*. The audit test achieves that a different and better way: every site carries a verdict, and each verdict is checked against the loaded class from both directions, so a wrong verdict fails on both bundles without the flag existing at all. Replace criterion 3 with: *"the audit is falsifiable — adding a `belongs_to` with no verdict fails a test, and contradicting a verdict fails a test."* That is met today and stays met.

(b) is defensible if someone wants the real 5.0 flag exercised, and it would be genuinely stronger. It is also a `test/dummy` config change that only ever runs on one bundle, and Phase 3's criterion 17 exists precisely because `test/dummy` fixes do not travel to consuming applications. **Not worth the exception.** Record the reasoning either way, because this will look like an oversight to the next reader.

### D2 — Criterion 4 gets a count tripwire rather than a rewrite

Criterion 4's "the count in the test matches 29" does not literally hold ([1.3](#13-criterion-4s-literal-check-does-not-match-the-audit-tests-design)). The reflection-based enumeration is better than a hardcoded list and should not be replaced by one. But the criterion's instinct — a reviewer can check one number — is worth keeping, so add the assertion rather than amending the criterion. One line, and it fails loudly if a declaration appears or disappears without the audit being revisited.

### D3 — What criterion 8's guard must actually assert

Per [1.6](#16-criterion-8s-guard-would-not-have-caught-15), "fails if `ColumnDumper` is undefined" tests for a failure mode that is not present. The guard must assert the **contract between the patch and the framework**: that the arity the patch defines is the arity the caller uses. Concretely — assert `ColumnDumper.instance_method(:column_spec).arity` matches what the running Rails version's `SchemaDumper` calls with, and fail with a message naming both.

Keep criterion 8's second half exactly as written. "A guard test that has never been seen to fail is not a guard" is right, and this guard is more worth breaking-and-watching than the original, because it is now guarding something real.

### D4 — How to scope the schema-dumper patch

**Needs a human.** The patch is a Ruby 2.7 frozen-string workaround for 4.2 only ([A.2](#a--settle-the-schema-dumper-contradiction-and-fix-b1)); 5.0's implementation does not have the bug and does not want the override.

**Options:**

| | Approach | Cost |
|---|---|---|
| (a) | Guard the patch on the Rails version — apply only below 5.0 | A version conditional in `lib/`, which reads against the spirit of "no version branches" even though criterion 11 scopes only `test/`/`spec/` |
| (b) | Make the patch signature-compatible with both — `def column_spec(column, types = nil)` and branch internally | One method, no load-time conditional, but the method now has two behaviours and a reader has to know why |
| (c) | Delete the patch and pin Ruby's frozen-string behaviour another way | Smallest surface, but re-opens a bug that was already fixed once, on the bundle that is in production |

⚠️ **Correction to (b), found while presenting these options.** It cannot delegate to Rails 5's implementation. Reopening a module and redefining a method **replaces** the original — `super` goes to the next ancestor, not to the definition just overwritten. So (b) would have to carry a verbatim copy of `activerecord-5.0.7.2/…/abstract/schema_dumper.rb:9-14` and manually re-sync it at 5.1, 5.2, 6.0, failing the same silent way if it ever drifts. (b) is worse than the table above implies.

**Recommendation: (a),** with the version check on `ActiveRecord::VERSION::MAJOR` rather than `NextRails.next?` — the patch is reacting to the *framework's* implementation, not to which bundle is booting, and those are different questions that happen to coincide right now. Phase 3 set the precedent for a non-`NextRails` conditional when the thing being branched on is not the dual-boot state (the gemspec's `NEXT_BOOT`).

> ### ✅ Decided: (a). Implemented in stage A.2.
> [`schema_dumper.rb`](../../lib/cms/extensions/active_record/connection_adapters/abstract/schema_dumper.rb) now wraps the override in `if ActiveRecord::VERSION::MAJOR < 5`, with the reasoning and the measured numbers in the file's own comment — including the instruction to **delete the file when 4.2 support is dropped rather than widening the guard.** Criterion 11's grep stays empty: nothing in `test/` or `spec/` branches on version.

### D5 — How far to take the truthiness audit

[1.9](#19-the-tasks_controller-failure-is-one-of-nine-sites-and-it-is-a-truthiness-bug) found nine sites; one is red.

**Options:** (a) fix only `tasks_controller.rb:22`; (b) fix all nine; (c) fix the four that feed a finder or an integer column, characterize the rest.

**Recommendation: (c).** (a) leaves eight known instances of a defect that is red in CI today — that is the "known hole vs unknown hole" distinction Phase 0 drew, on the wrong side of it. (b) is a nine-site behaviour change in a phase whose contract is characterization, and five of the nine have no test that would notice a mistake. (c) fixes what can fail the same way and writes the rest down.

> ### ✅ Resolved: (c), and the premise changed underneath it.
> The probe in [B.3](#b--the-ten-rails-5-failures-work-item-40) showed **both bundles crash identically** on an explicit blank param, so this was never a 4.2-behaviour question — 4.2 has the same live 500. That removed the reason this needed a second opinion, and (c) was applied on its merits: **six** sites fixed (not the four estimated — the audit found six that reach a finder or an integer column), three documented. The one to watch is `users_controller.rb:15`, where a blank `?show_expired=` silently shows expired users on both bundles; it is one word from fixed but changes what a URL does, so it wants an owner rather than a quiet edit.

### D6 — Does Phase 4 fix the cluster, or only characterize it?

Work item 4.0 says "characterize before fixing", which implies both. Worth stating explicitly, because the cluster is a genuine Rails 5 semantic difference in optimistic locking and the fix might be larger than this phase wants.

**Recommendation: fix it, and hold the line at 4.2 behaviour.** Criterion 13 requires the job green, so characterizing without fixing does not close the phase. But if the fix turns out to require changing what 4.2 does, **stop and escalate** — that is a Phase 5 decision (it is a behaviour change that ships), not a Phase 4 one. Criterion 14 is the tripwire: every fix needs a 4.2-asserting test that passes on the `Gemfile` bundle.

> ### ✅ Decided: fix the cluster, leave the locking defect.
> The fix re-reads the locking column before the after_save touch, so a stale save proceeds exactly as it does on 4.2 today. **Optimistic locking stays silently defeated** — two editors on one page, second writer wins, no conflict raised. That is a real data-integrity defect and it is now pinned by a characterization test that fails if anyone makes conflicts raise, with a failure message pointing back here. Escalating it properly is the follow-up this phase owes; it is not a Rails-upgrade decision.
>
> ### ✅ Follow-up closed by CMS-435 (2026-09-24). See [cms-435-optimistic-locking.md](cms-435-optimistic-locking.md).
> The escalation happened and the answer was **yes, make it raise** — gated on the caller having assigned `lock_version`, which is what a form round-trip does and what internal engine code never does. The characterization test this phase wrote has been deleted, as designed: its failure was the signal.
>
> Phase 4 read the defect as one problem. It was **three**, and this phase could only have seen the first: AR's check never runs on a versioned save (`create_or_update` INSERTs a version row rather than UPDATEing the content row), `build_object_from_version` left `lock_version` at the column default so both edit forms posted back a constant 0, and an *unconditional* raise breaks `PageComponent#save`. Fixing the save path alone — the obvious reading of this row — would have produced a check with nothing to check against.

### D7 — ~~What happens if stage A finds the dumper working~~ — resolved

**Struck. Settled by measurement during planning** ([1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50)): the dumper is broken on 5.0, totally and silently. No decision needed.

Kept as a row rather than deleted because its reasoning is what the stage-A test has to encode: *"'it seemed fine' is exactly what that failure looks like from the outside."* That turned out to be literally true — the dump exits 0 and writes a valid file. Any test weaker than an assertion on dumped content reproduces the same blind spot.

---

### D8 — The `move_to_position` dedupe: fix, or characterize?

`nodes_to_update_on_success` returns the siblings the front end must reposition. A node that is a sibling in **both** the previous and the target parent — which is every move *within* one folder — appears twice, and the `.distinct` that looks like it prevents that is inside the parentheses and cannot. Phase 3 diagnosed it, declined to change behaviour mid-rename, and routed it here.

#### First, the rule this phase actually applies

An earlier draft of this decision said "a behaviour change to the shipping 4.2 bundle is not Phase 4's to make." **That is wrong, and the record contradicts it.** Stage B changed 4.2 behaviour ten times and stage G changed it again. [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it) draws the line in a different place:

> if the fix turns out to require **changing what 4.2 does**, stop and escalate

— which in practice has meant **does anyone's working behaviour change?** Every fix this phase has made preserves what 4.2 does for a user today:

| fix | why it was in scope |
|---|---|
| The locking cluster (B.1) | 4.2 already ended at the same `lock_version`; the fix only stops 5.0 raising on the way |
| The six truthiness guards (B.3) | `?some_id=` was a **500** on both bundles. A crash is not a behaviour anyone depends on |
| `quote_value` → `connection.quote` (B.4) | An ArgumentError swallowed by a bare rescue. Same — nothing worked before |
| Both partial paths (B.2, stage G) | `MissingTemplate`. Same again |

And every defect it declined is one where the repair **would** change working behaviour, or needs a decision about what the behaviour should be: optimistic locking ([D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it)), `version_comment` (switches on a skip-save branch that has never run), `publish`'s `rescue Exception`, `exists?`'s signature and its `count` vs `LIMIT 1` contract.

So the question here is not "is this a behaviour change" — it is — but **whose behaviour changes.**

#### Second, Phase 3's note is ambiguous and should not be read as an instruction

> Hoisting it outside the parens would fix that, and is a behaviour change rather than a rename, so it belongs with the characterization test Phase 4 already owns for `move_to_position`.

Two readings. Either "it is a behaviour change, **so Phase 4 should make it**", or "it is a behaviour change **and I was only doing renames**, so it goes to whoever next opens this method." The second is what Phase 3's scope supports, and the first would have Phase 3 assigning Phase 4 work that the phase document does not list. **Take it as a routing note, not an instruction** — it identifies the right desk, and this decision is still ours to make.

#### The decision

The payload is JSON consumed by front-end JavaScript. Everything turns on what that consumer does with a repeated `[id, position, depth]` triple, and **nothing in this plan has read it**.

| if the consumer… | then the current behaviour is… | and |
|---|---|---|
| **assigns** position/depth per entry (idempotent) | cosmetic — a duplicate write of the same values | the fix is free and changes nothing observable → **fix it** |
| **accumulates**, animates, or counts | a **live user-facing bug** on every within-folder move | the fix is the whole point → **fix it**, and say so loudly |

**Recommendation: read the consumer first, then fix in either case.** The branches differ in how the change is *described*, not in what is done — which is what makes this different from the defects this phase has left standing. Those had a genuine open question about what the behaviour *should* be. Here nobody would argue for the duplicate: the intent is written into the code, because the dedupe call is already there and was meant to work.

Characterizing instead would mean writing a test that asserts a misplaced parenthesis is correct. Phase 4 has enshrined current behaviour several times, but always where repairing it was contested. Enshrining a typo is not the same act, and the precedent that fits is B.2 — an obviously-wrong one-line path on a branch nothing reaches, fixed in stage G with a test that reaches the branch deliberately.

⚠️ **Escalate rather than proceed if reading the consumer shows a third case** — if the front end depends on the duplicate, this stops being Tier C and becomes a Phase 5 conversation.

Either way the `TODO(Phase 4)` marker comes out: the phase it names is this one, and a marker that outlives its phase is worse than no marker.

---

### D9 — `Cms::Section#pages` returns rows in arbitrary order

Found during [stage I](#i--exit-and-the-tier-c-error-branches), and not by looking for it. A full `ci:test` run failed on [`sitemap_test.rb`](../../test/unit/lib/cms/sitemap_test.rb)'s `"pages"` test with two pages transposed — identical timestamps, no tiebreaker — and passed the next nine runs.

**Nothing in this phase caused it.** Both the test and the method are untouched by Phase 4. The cause is that `Section#pages` collects straight off ancestry's `children`, which carries no `ORDER BY`, so PostgreSQL returns the rows in whatever order it likes.

It is the **only** reader on that class which does not order. [`child_sections`](../../app/models/cms/section.rb#L71), [`visible_child_nodes`](../../app/models/cms/section.rb#L143) and [`section.rb:226`](../../app/models/cms/section.rb#L226) all chain `.in_order` — `order("position asc")` on `SectionNode`. That is what makes the omission read as an oversight rather than a decision.

**Decision: fixed, on the user's call, having been raised rather than absorbed.**

This is a behaviour change to the 4.2 bundle that ships, and no Phase 4 work item covers it — so it was surfaced as a question rather than folded in quietly, the same way [D8](#d8--the-move_to_position-dedupe-fix-or-characterize) was. What made it cheap to say yes to:

- **Nothing in the engine calls it.** `grep -rn "\.pages\b" app/ lib/` finds only the test. A downstream caller gets a stable sitemap order where it previously got an arbitrary one, which is the direction nobody argues about.
- **`#child_nodes` is deliberately left alone.** It is also unordered, but every order-sensitive caller adds `.in_order` itself, and the rest only ask it for `.count` or `.empty?`.

The test now asserts position order **against** insertion order, so removing `.in_order` turns it red rather than leaving it to luck. Verified by sabotage.

**The general point is worth keeping.** A test that passes nine runs in ten is not green, it is unmeasured — and this one had presumably been unmeasured for years. It surfaced only because this phase runs the full chain after every stage, which [§2](#2-execution-order) required for an unrelated reason.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| **R1** | 🔴 **`test/dummy/db/schema.rb` gets committed with every table commented out.** Confirmed live in [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50): any `db:migrate` on the 5.0 bundle rewrites the file with 0 of 74 tables and **exits successfully**. It nearly happened once already ([§9](phase-3-report.md)). Committing it would break every developer's database and every downstream CI run, and the commit would look clean | Three layers, because the failure is silent: (1) check `git status` before **every** commit, not at exit; (2) land A.2 early, which removes the cause; (3) A.3's content assertion, which is the only thing that would catch a regression automatically. Until A.2 lands, **do not run `db:migrate` on `Gemfile.next`** — use `db:install`, or capture the dump to a `StringIO` as the planning run did |
| **R2** | **A fix greens 5.0 by changing 4.2.** The cluster is in save/locking, the highest-traffic path in the engine | Criterion 14, and [D6](#d6--does-phase-4-fix-the-cluster-or-only-characterize-it)'s escalation rule. Re-run the 4.2 suite after every stage |
| ~~**R3**~~ | ~~The eager-load test is red and its findings are large.~~ **Did not happen** — `eager_load!` runs clean on both bundles. The risk that did materialise was not on this list: the test is green but **widens the coverage denominator**, which is why it is deferred. See [stage C](#c--the-eager-load-test-work-item-42--written-here-enabled-in-stage-f) | Replaced by the stage F re-measure |
| **R4** | **[D4](#d4--how-to-scope-the-schema-dumper-patch)'s version branch reads as a violation.** A reviewer sees a Rails-version conditional in `lib/` in a phase that forbids version branches | The distinction is real and must be written into the patch's comment: it branches on the *framework's implementation*, not on which bundle is booting. Criterion 11's grep stays empty either way |
| **R5** | **Criterion 14 is unfalsifiable if written loosely.** "Was it characterized first?" is a claim about process, not about the tree | Make it checkable: for each of the ten, name the test and show it passing on the `Gemfile` bundle. A test that only runs on `Gemfile.next` does not satisfy it |
| **R6** | **The two new Forms test files raise coverage and mask a drop elsewhere.** Aggregate coverage can rise while a file regresses | Measure on a cleared resultset, and check the two Forms controllers specifically (criterion 7) rather than reading the aggregate |
| ~~**R7**~~ | ~~**B.2's partial fix is mistaken for a cluster fix.** It changes the functional failures' message without passing them~~ | **Did not arise, because the ordering held.** B.1 landed first and cleared all seven, which removed the only path to the partial; the fix then landed alone in [stage G](#g--the-versioning-call-chain-tests-work-item-46-and-b2) with a test that reaches the branch deliberately. The risk's real payoff was elsewhere: deferring it meant reading the file again, which is how the **second** broken partial reference was found |

---

## 6. Contingencies

**If the cluster's fix requires changing 4.2 behaviour** — stop, write up the choice, and take it to Phase 5. Criterion 13 goes unmet and the job stays red, which is the same outcome Phase 3 reached honestly. Do not change what ships to turn a CI job green.

**If stage A finds the dumper broken on 5.0 and the fix is not backwards-compatible** — that is a genuine surprise worth escalating rather than absorbing. The patch is a workaround for a bug in a Ruby/Rails combination that is on its way out; "delete it at the 5.0 bump" may beat "branch it now."

**If `portlets_with_params` resists diagnosis** — it is the least-connected of the ten and the only one with no hypothesis attached. Time-box it. If it does not yield, tag it and record the number, the way Phase 0 handled `@cli`: a documented, tagged, counted failure is a known hole. But note that criterion 13 wants the job **green**, so a tagged scenario has to be excluded from the gating profile deliberately and said out loud — not quietly.

**If the eager-load test cannot be made green on either bundle** — it still ships, red or excluded, with its output recorded. Its value is the inventory it produces for the 6.0 hop, and that value does not depend on it passing today.

---

## 7. Exit criteria traceability

Criteria as they stand in [`phase-4-characterization-tests.md`](phase-4-characterization-tests.md) after Phase 3's handoff, with the two amendments this plan proposes marked.

| # | Criterion | Stage | Verification |
|---|---|---|---|
| 1 | Suite green on both Gemfiles | B, I | ✅ **Met, with a caveat.** Identical on both: 838 unit / 145 spec / 139 functional / 7 orphan / 154 cucumber, 0F/0E. ⚠️ **Two of ~14 full runs failed on pre-existing intermittent unit tests.** One cause was found and fixed ([D9](#d9--cmssectionpages-returns-rows-in-arbitrary-order)); the other was not isolated. Written up in [§6 of the report](phase-4-report.md) with a recommendation for Phase 5 |
| 2 | Coverage at or above Phase 2, branch reported | I | ✅ **Met on line, re-baselined then raised twice on branch.** Line **78.44% → 83.94%**. Branch 70.89% → **70.97%**, via 70.49 in [F](#f--parameters-on-the-four-uncovered-sites-work-item-44) and 70.63 in [H](#h--the-rest-of-tier-b-work-items-45-47). The drop and both raises are reasoned beside `COVERAGE_MINIMUM_BRANCH` in [`core_tasks.rake`](../../lib/tasks/core_tasks.rake) |
| 3 | ~~Flag set in the test environment~~ → **audit is falsifiable** | D | [D1](#d1--criterion-3-is-replaced-by-the-audit-tests-invariant). ⚠️ **Amended** — the original cannot be met; see [1.2](#12-criterion-3-rests-on-a-misreading-and-phase-3-already-measured-it) |
| 4 | All 29 have an explicit test; count matches 29 | D | The audit test's six invariants + the count tripwire ([D2](#d2--criterion-4-gets-a-count-tripwire-rather-than-a-rewrite)) |
| 5 | Eager-load test exists and passes | C, F | ✅ **Met in [stage F](#f--parameters-on-the-four-uncovered-sites-work-item-44).** Written in C and held out of the gated suite until the branch baseline was re-measured rather than worked around |
| 6 | `create_content_table` exercised with every option combination | E | ✅ **Met.** The DSL takes exactly two options, so the matrix is 2×2 and is enumerated in full; each case asserts the **complete** column set on both tables |
| 7 | Four `Parameters` sites tested; both Forms controllers off 0% | F | ✅ **Met.** `form_fields_controller` 0% → 42.6%, `forms_controller` 0% → 72.7%. An **eleventh** B9 site was found at `content_block_controller.rb:275`, a 5.1 breakage |
| 8 | Guard test, **proven to guard** | A.4 | ✅ **Met.** [D3](#d3--what-criterion-8s-guard-must-actually-assert). ⚠️ **Amended** — asserts the signature contract, not the constant ([1.6](#16-criterion-8s-guard-would-not-have-caught-15)). Seen red in both directions |
| 9 | Schema dump asserted end-to-end for boolean-default columns | A.3 | ✅ **Met** — [`schema_dumper_test.rb`](../../test/unit/schema_dumper_test.rb), 6 tests green on both bundles. Asserts dumped **content**; "does not raise" and "output is non-empty" both pass on the broken bundle and are rejected in the header comment ([1.6](#16-criterion-8s-guard-would-not-have-caught-15)) |
| 10 | B6 audit written down, three questions answered | G | ✅ **Met** — answered in [stage G](#g--the-versioning-call-chain-tests-work-item-46-and-b2) and in [`versioning_call_chain_test.rb`](../../test/unit/behaviors/versioning_call_chain_test.rb)'s header. All three were unasserted; two behave correctly, `version_comment` does not on the CMS edit path |
| 11 | Every new test is a characterization test | I | ✅ **Met.** `grep -rn "NextRails" test/ spec/` returns 0 |
| 12 | No test written for a loud failure | I | ✅ **Met.** The only matches for `update_attributes` in the test tree (`portlet_test.rb:79`, `sitemap_test.rb:86`) both predate this phase; the diff `00c5e5b1..HEAD` adds no line matching `*_filter`, `update_attributes` or `File.exists?` |
| 13 | **The gating `next-rails` job is green** | B | ✅ **Met.** All ten resolved, plus an order-dependent flake that would have made the job green only on lucky seeds. Arrived from Phase 3 as its criterion 16 |
| 14 | **Each of the ten characterized before it was fixed** | B | ✅ **Met.** Per failure, a named test passing on the `Gemfile` bundle. Note three of the four causes were 4.2 defects, so those tests assert *corrected* behaviour on both bundles rather than pinning 4.2 — called out per item rather than blurred ([R5](#5-risks)) |

**A note on criteria 3 and 8.** Both are amended by this plan rather than met, and both amendments came out of measurement — 3 from Phase 3's stage-B work, 8 from [1.5](#15-b1-is-an-arity-collision-not-a-vanishing-monkeypatch-and-it-is-live-on-50). That is two of fourteen criteria rewritten before the phase starts, which is worth pausing on: it is the same pattern as Phase 3, where measurement moved four work items and struck one. **The phase documents were written before anything ran, and they are hypotheses.** Amend them in the open, with the evidence attached, and the record stays trustworthy. What must not happen is a criterion being quietly reinterpreted to something achievable.
