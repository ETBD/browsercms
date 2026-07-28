# Test Coverage Plan — browsercms

**Date:** 2026-07-28
**Source:** `coverage/index.html` + `coverage/.resultset.json`, produced by the run at `d0d108cc [CMS-420] tests are running`
**Suites merged:** Unit Tests, RSpec, Functional Tests, Cucumber Features (4 suites, 219 files, all of `app/` + `lib/`)
**Ordering principle:** coverage gained per unit of effort. Cheapest first.

This supersedes the estimates in `TEST_COVERAGE_ANALYSIS.md`, which were static guesses made before the suite ran. Those numbers were wrong in both directions.

---

## 1. Where we actually stand

| Group | Files | Relevant lines | Covered | Missed | % |
|---|---|---|---|---|---|
| Models | 47 | 1,601 | 1,470 | 131 | **91.82%** |
| Libraries | 91 | 2,901 | 2,119 | 782 | **73.04%** |
| Ungrouped (inputs, portlets, presenters) | 18 | 207 | 135 | 72 | **65.22%** |
| Helpers | 17 | 587 | 339 | 248 | **57.75%** |
| Controllers | 46 | 1,447 | 835 | 612 | **57.71%** |
| **All files** | **219** | **6,743** | **4,898** | **1,845** | **72.64%** |

The distribution is concentrated. **The top 10 files hold 44% of all missed lines; the top 30 hold 69%.** That is good news: this is a short list of targeted jobs, not a 219-file slog.

### 1.1 The headline number is misleading in two directions

**465 of the 1,845 "missed" lines do not exist as code.**

Thirty-five files have 0.00% coverage. For every one of them, SimpleCov reports `relevant lines == total lines`, including blank lines, comments, and bare `end`s:

```
lib/cms/version.rb          loc=11  relevant=11  (the file is 4 lines of code and 7 of comment/blank)
app/models/cms/templates.rb loc=31  relevant=31  (really ~22)
lib/cms/module_installation.rb loc=31 relevant=31 (really ~8)
```

This is what SimpleCov does for a file it never loaded — with no `Coverage` data to work from, it marks every line missed. Estimating real relevant lines by stripping blanks, comments, and non-executable keywords gives **640, not 1,105**. So the honest baseline, once those files are merely *loaded* by anything, is closer to **78%** than 72.64%.

Practical consequence: the percentage will move faster than the missed-line count suggests, because the denominator shrinks as well as the numerator growing.

**In the other direction: coverage is inversely correlated with upgrade risk.** Models — the layer least changed by Rails 5→8 — are at 92%. Controllers, where `get :action, params: {}`, strong parameters, `render :text`, and `before_filter`→`before_action` all bite, are at 58%. The 612 missed controller lines are the ones the upgrade will actually break.

---

## 2. Phase 0 — fix the harness before writing a single test

None of this is test-writing. All of it changes the number and the signal, and all of it should land first because it changes what the rest of the plan is measuring against.

### 0a. Filter generator *templates* out of coverage — 30 minutes

Four files under coverage are not library code. They are ERB-adjacent templates copied into a user's application by a generator, and are only executed inside a freshly generated Rails app:

| File | Counted lines |
|---|---|
| `lib/generators/browser_cms/demo_site/templates/demo.seeds.rb` | 249 |
| `lib/templates/active_record/model/model.rb` | 17 |
| `lib/generators/cms/portlet/templates/portlet.rb` | 12 |
| `lib/generators/cms/portlet/templates/portlet_helper.rb` | 5 |
| **Total** | **283** |

`demo.seeds.rb` alone is the single largest "gap" in the report — **13.5% of all missed lines** — and it is a seed script. Loading it would execute it. Testing it means running `rails g browser_cms:demo_site` and asserting on the resulting database, which the `@cli` cucumber features already do out of process.

In `.simplecov`:

```ruby
SimpleCov.start 'rails' do
  add_filter %r{^/lib/generators/.*/templates/}
  add_filter %r{^/lib/templates/}
end
```

**72.64% → 75.82%**, no tests written.

### 0b. Delete dead code instead of testing it — 1 hour

| File | Counted lines | Why |
|---|---|---|
| `lib/cms/commands/to_version400.rb` | 10 | Upgrade command for BrowserCMS 4.0.0. Two majors dead. |
| `app/portlets/deprecated_placeholder.rb` | 12 | Named for its own obsolescence. |

Both are already zero-coverage. A Rails 8 upgrade is exactly the right moment to remove them. Also review `lib/cms/form_builder/deprecated_inputs.rb` (45%, 12 missed) and `app/inputs/cms_text_area_input.rb` (0%, 10 missed) — but note `features/content_blocks/deprecated_form_inputs.feature` exists, so the deprecated inputs are still contractually alive. Test those; delete the other two.

**→ 76.08%**

### 0c. Decide what to do about `lib/generators` — 1 hour to decide

Five generator files sit at 0%, totalling 198 counted lines (~102 real):

```
lib/generators/cms/content_block/content_block_generator.rb  103
lib/generators/cms/portlet/portlet_generator.rb               38
lib/generators/cms/template/template_generator.rb             29
lib/generators/cms/install/install_generator.rb               16
lib/generators/browser_cms.rb                                 12
```

**They are not untested.** `features/generators/*.feature` and `features/commands/*.feature` cover them — five and four files respectively. Two things hide that from the report:

1. The default `rake features` task excludes them: `--tags ~@cli`.
2. Even when run, they execute via **aruba**, which shells out to `rails g ...` in a **child process**. SimpleCov in the parent process cannot see child-process coverage. (The pinned `simplecov (0.12.0)` predates `SimpleCov.at_fork` entirely, so there is no configuration escape hatch short of a `.simplecov` inside each generated app.) Generator coverage will read 0% no matter how thoroughly cucumber exercises them.

Two honest options:

- **Exclude** `lib/generators` from coverage and rely on the `@cli` features (which should be re-enabled in CI regardless). **→ 78.49%**
- **Add in-process tests** using `Rails::Generators::TestCase` — `test/test_helper.rb:17` already does `require "rails/generators/test_case"`, so the harness is ready. (`test/unit/generators/install_generator_test.rb` is *not* a head start: despite the filename it is an `ActiveSupport::TestCase` asserting on `default_engine_path`, and never invokes a generator.) This is real work (see Phase 7) but it is fast, in-process, debuggable, and it is where Rails 8's generator API changes (`hook_for`, `Rails::Generators::ResourceHelpers`, `File.exists?` → removed) will surface. `content_block_generator.rb:26` calls `File.exists?` — **that method is gone in modern Ruby**, and nothing in the measured suite touches it.

Recommendation: exclude for now to get an honest denominator, and schedule Phase 7. Do not leave it at 0% and pretend it is a coverage gap — it is a *measurement* gap with one genuine landmine in it.

### 0d. Wire up the orphaned tests — 2 hours

`Rakefile` only globs three patterns:

```ruby
t.pattern = 'test/unit/**/*_test.rb'
t.pattern = 'spec/**/*_spec.rb'
t.pattern = 'test/functional/**/*_test.rb'
```

Ten test files are therefore outside the `rake test` / `rake ci:test` chain entirely:

```
test/assumptions_test.rb
test/helpers/cms/content_types_helper_test.rb
test/dummy/test/controllers/design_controller_test.rb
test/dummy/test/functional/cms/catalogs_controller_test.rb
test/dummy/test/functional/content_page_controller_test.rb
test/dummy/test/helpers/design_helper_test.rb
test/dummy/test/models/deprecated_input_test.rb
test/dummy/test/unit/helpers/content_page_helper_test.rb
test/dummy/test/unit/portlets/find_category_portlet_test.rb
test/dummy/test/unit/portlets/uses_helper_portlet_test.rb
```

A distinction worth drawing: `test/assumptions_test.rb` and `test/helpers/cms/content_types_helper_test.rb` are genuinely unreachable — no task can run them. The eight `test/dummy/test/**` files *are* reachable via `rake app:test` (the `Rakefile` sets `APP_RAKEFILE` to the dummy app and loads `engine.rake`), but nothing in the `rake test` chain invokes it, and it played no part in the coverage run. Wire `app:test` into `rake test`, and add a fourth `Rake::TestTask` for `test/helpers/**` and the root-level test.

Expect this to hurt before it helps. `test/helpers/cms/content_types_helper_test.rb` is:

```ruby
it "must be a real test" do
  flunk "Need real tests"
end
```

It will fail the moment it is wired in. That is the point — a red test is information, an unrun test is not. The `test/dummy/**` tests cover the engine-host integration path (`acts_as_content_page`, custom portlets, design helpers), which is precisely the surface a Rails 8 upgrade of a *mountable engine* threatens.

### 0e. Re-enable the commented-out Forms feature — 30 minutes to confirm scope

`features/content_blocks/forms.feature` has every scenario commented out under the header:

```gherkin
# Forms a broken
```

This single act of commenting-out is why three controllers are at exactly 0.00% and why the Forms subsystem is the largest genuine gap in the codebase. Whatever "broken" meant, it needs a ticket, not a comment block.

**Phase 0 total: 72.64% → ~78.5%, zero new tests, roughly one day of work.**

---

## 3. The ordered backlog

> **Superseded for sequencing by `RAILS_UPGRADE_TEST_PRIORITY.md`.** The order below maximises coverage gained per hour worked, which is the right lens for paying down debt but the wrong one for validating a Rails upgrade. That document re-ranks the same work by breakage risk, and — importantly — establishes that the **test harness itself must be migrated before any of this is worth writing** (`mocha 1.2.0`, `factory_girl 4.7.0`, `cucumber 2.4.0` and the positional controller-test call style will not run on Rails 8). Use this section for effort estimates and per-file detail; use that one for what to do first.

Percentages below are cumulative and assume Phase 0 is done (baseline 78.49%, 4,898/6,240). Each phase models realistic per-file targets, not 100%.

| # | Phase | Effort | Missed lines addressed | Cumulative |
|---|---|---|---|---|
| 1 | Pure-Ruby quick wins | ~2 days | ~180 | **81.1%** |
| 2 | Forms subsystem controllers | ~4 days | 249 | **84.4%** |
| 3 | Remaining 0% controllers | ~3 days | 173 | **86.9%** |
| 4 | Partially-covered controllers | ~5 days | 187 | **89.0%** |
| 5 | Helpers | ~4 days | 194 | **91.6%** |
| 6 | Long tail — inputs, portlets, behaviors | ~4 days | 145 | **93.2%** |
| 7 | In-process generator tests | ~3 days | (restores 198 excluded lines at ~70%) | — |

---

### Phase 1 — Pure-Ruby quick wins (~2 days, → 81.1%)

No HTTP, no fixtures, no view context. Highest lines-per-hour in the codebase. Do these first; they build momentum and they are safe to hand to whoever is least familiar with the codebase.

| Rank | Target | Missed | Effort | Notes |
|---|---|---|---|---|
| 1 | `app/models/cms/templates.rb` | 31 | 15 min | `self.default_body` is a pure heredoc. One assertion covers 23 lines. |
| 2 | `lib/cms/module_installation.rb` | 31 | 1 h | 16 of 31 are class body — a bare `require` covers them. `mount_engine` needs a stubbed generator. |
| 3 | `lib/cms/acts/cms_user.rb` | 16 | 2 h | `able_to_view?` (7), `able_to?` (3). `test/unit/behaviors/cms_user_test.rb` already exists — extend it. Permission logic; worth real assertions, not smoke tests. |
| 4 | `lib/acts_as_list.rb` | 16 | 3 h | `first?`, `last?`, `bottom_position_in_list`, `decrement_positions_on_higher_items`, `insert_at`. Vendored gem — **and `acts_as_list` semantics change under Rails 8's `touch`/`optimistic locking` defaults.** Higher upgrade value than its size suggests. |
| 5 | `app/models/cms/section_node.rb` | 13 | 2 h | `move_before` (4), `move_after` (4). Sitemap integrity. |
| 6 | `lib/cms/version.rb` | 11 | 5 min | `assert_match /\d+\.\d+\.\d+/, Cms.version`. Currently 0% because nothing requires it at test time. |
| 7 | `lib/cms/behaviors/dynamic_attributes.rb` | 11 | 3 h | `nonversioned_class` (5). Touches `method_missing` + `read_attribute` — **`ActiveRecord` attribute API is one of the most-changed areas 4.2→8.** |
| 8 | `lib/cms/behaviors/hiding.rb` | 10 | 1 h | `hide!`, `unhide`, `unhide!` — three one-line bang methods. |
| 9 | `app/models/cms/attachment.rb` | 9 | 2 h | `configuration_value`, `dynamically_return_styles`, `public?`. |
| 10 | `app/models/cms/content_type.rb` | 9 | 1 h | `self.find_by_key` (3), `content_block_type_for_list` (3). `content_type_spec.rb` exists. |
| 11 | `app/models/cms/page.rb` / `section.rb` | 8 + 8 | 3 h | Already 96%/94%. Cheap top-up on well-understood models. |
| 12 | `app/models/cms/portlet.rb` | 18 | 3 h | `store_hash_in_flash`, `url_for_success/failure`, `self.get_subclass`. Flash-based control flow — fragile across upgrades. |
| 13 | `app/presenters/cms/user_presenter.rb` | 3 | 15 min | `as_json`. `spec/cms/presenters/user_presenter_spec.rb` exists. |
| 14 | `lib/sequence.rb` | 6 | 15 min | 4 real lines. |
| 15 | `app/helpers/cms/content_types_helper.rb` | 4 | 10 min | **The module is empty.** Delete it and its flunking test, or give it a reason to exist. |

### Phase 2 — Forms subsystem (~4 days, → 84.4%)

The largest genuine gap in the codebase: **249 missed lines across three controllers, all at exactly 0.00%**, because `forms.feature` is commented out (§0e).

Mitigating factor that makes this cheaper than it looks: the *models* are well specified. `spec/cms/form_spec.rb`, `form_fields_spec.rb`, and `form_entry_spec.rb` all exist and pass, and `test/factories/factories.rb` has a `:form` factory. You are writing controller tests against known-good models.

Aggravating factor: `Cms::FormField` and `Cms::FormEntry` have **no factories** — `form_entry_spec.rb` builds them inline via `Cms::FormEntry.for(form)`. Add factories first.

| Rank | Target | Missed | Effort | Notes |
|---|---|---|---|---|
| 16 | `app/controllers/cms/form_entries_controller.rb` | 140 | 2 d | `submit` (23), `bulk_update` (18), `index` (14), `update` (9), `create` (9), `columns_for_index` (8), `save_entry_failure` (6). `submit` is the **public, guest-accessible** endpoint (`allow_guests_to [:submit]`) — highest-value single test in the repo. It also sends mail via `Cms::EmailMessage.create!`, so needs `ActionMailer` assertions. |
| 17 | `app/controllers/cms/form_fields_controller.rb` | 74 | 1 d | `create` (17), `update` (10), `insert_at` (9), `destroy` (6). All JSON/AJAX. `render json:` behaviour and `params[:form_field].delete(:form_id)` — **mutating `ActionController::Parameters` in place is not permitted the way it was in 4.2.** This code will break on upgrade. |
| 18 | `app/controllers/cms/forms_controller.rb` | 35 | 1 d | `new` (10) — unconventional: `new` writes to the database (`@block.save!`) to enable AJAX field association. `associate_form_fields` (8) does `params[:field_ids].split(" ")`. Two `before_filter`s to convert. Test the weirdness before changing it. |

### Phase 3 — Remaining 0% controllers (~3 days, → 86.9%)

Small, self-contained, and each one follows the existing `test/functional/cms/*_test.rb` pattern — `ActionController::TestCase` + `include Cms::ControllerTestHelper` (defined at `test/test_helper.rb:170`), with `create(:user)` / `create(:section)` factories for setup. Good parallel work for multiple people.

| Rank | Target | Missed | Effort | Notes |
|---|---|---|---|---|
| 19 | `app/controllers/cms/page_route_options_controller.rb` | 58 | 1 d | `create` (10), `update` (9), `destroy` (7), `object_name` (6). Uses `update_attributes` — **removed in Rails 7.** Also metaprogrammed `resource`/`object_name`, plus two sibling controllers (#23) inherit from it. |
| 20 | `app/controllers/cms/portlet_controller.rb` | 21 | 4 h | `execute_handler` (16). **This is a security boundary** — it dispatches `@portlet.send(params[:handler])` and guards it with a `method_defined?` blacklist. It has never been tested. Write the "handler must not reach a private/inherited method" test regardless of coverage goals. |
| 21 | `app/controllers/cms/page_components_controller.rb` | 20 | 4 h | `update` (10), `new` (5). `respond_to :json` / `respond_with` — extracted from core into the `responders` gem. It works today only because `devise 4.9.4` pulls in `responders 2.4.1` transitively; nothing declares it. **Declare `responders` explicitly in the gemspec before the upgrade**, or this breaks the moment Devise's dependencies shift. |
| 22 | `app/controllers/cms/content_types_controller.rb` | 18 | 3 h | `index` (9). `format.js { render layout: false }`. Trivial once a `ContentType` exists. |
| 23 | `app/controllers/cms/toolbar_controller.rb` | 18 | 3 h | `index` (11). Reads five `params` keys and `Page#as_of_version`. Pure read path. |
| 24 | `app/controllers/cms/passwords_controller.rb` | 22 | 1 d | Subclasses `Devise::PasswordsController`. Only ~13 real lines and all four methods just `use_page_title` then `super`. **Effort is all in the Devise-in-an-engine test setup**, not the assertions. Consider deferring — low value, high friction. |
| 25 | `app/controllers/cms/user_controller.rb` | 8 | 30 min | One action, `render json: Cms::UserPresenter.new(current_user)`. Pair with #13. |
| 26 | `page_route_conditions_controller.rb` + `page_route_requirements_controller.rb` | 4 + 4 | 30 min | Two lines each; both inherit from #19. Free once #19 is done. |

### Phase 4 — Partially-covered controllers (~5 days, → 89.0%)

Each of these already has a test file. You are extending, not creating — which means the setup cost is paid and the effort is genuinely per-assertion. The named methods below are the untested ones.

| Rank | Target | Missed | Effort | Untested methods |
|---|---|---|---|---|
| 27 | `content_block_controller.rb` (84%) | 30 | 1 d | `bulk_update` (11), `update` (4), `after_update_on_edit_conflict` (2), `after_update_on_error` (2). The **edit-conflict and error paths are exactly what silently changes** when `ActiveRecord` validation/callback ordering shifts. |
| 28 | `connectors_controller.rb` (38%) | 24 | 1 d | `destroy` (17), `create` (7). 17 missed lines in one `destroy` means a deep branch tree around connector ordering. |
| 29 | `section_nodes_controller.rb` (41%) | 20 | 1 d | `move_to_position` (9), `slow_index` (6), `repair_sitemap` (3). Drag-and-drop sitemap reordering; pairs with #4 and #5. |
| 30 | `resource_controller.rb` (70%) | 19 | 1 d | `create`/`update`/`destroy` (4 each). **Base class for most CMS controllers** — every line covered here is leverage on every subclass. |
| 31 | `inline_content_controller.rb` (29%) | 17 | 4 h | `update` (15). One method, 15 branches. Mercury/inline editing path. |
| 32 | `pages_controller.rb` (86%) | 13 | 4 h | `update` (3), `destroy` (3), `strip_visibility_params` (3). `strip_visibility_params` is **strong-parameters manipulation — a Rails 5 flashpoint.** |
| 33 | `users_controller.rb` (84%) | 11 | 4 h | `disable` (4), `enable` (2), `update_password` (1). |
| 34 | `attachments_controller.rb` (64%) | 9 | 4 h | `create` (5), `destroy` (3). File upload — `Rack::Test::UploadedFile` API changes. |
| 35 | `sections_controller.rb` (84%), `content_controller.rb` (92%), `links_controller.rb` (85%), `dynamic_views_controller.rb` (84%) | 9+8+7+7 | 1 d | Top-up work. `content_controller#preview` (4) is the notable one. |

### Phase 5 — Helpers (~4 days, → 91.6%)

Helpers are 57.75% — tied with controllers for worst — but the effort profile is completely different. `ActionView::TestCase` gives you the view context for free (see `test/unit/helpers/menu_helper_test.rb` for the pattern), and helper methods are mostly pure string/tag builders. **The catch: assertions on generated HTML are brittle**, and these helpers emit Bootstrap-2-era markup that a Rails 8 upgrade may well change. Assert on structure (`assert_select`), not on exact strings.

| Rank | Target | Missed | Effort | Untested methods |
|---|---|---|---|---|
| 36 | `ui_elements_helper.rb` (51%) | 43 | 1 d | `delete_menu_button` (14), `publish_menu_button` (6), `versions_menu_button` (6), `edit_content_menu_button` (4), `view_content_menu_button` (4), `select_content_type_tag` (4). Six independent button builders — parallelizable, and `delete_menu_button` alone is 14 lines. Best single helper target. |
| 37 | `section_nodes_helper.rb` (30%) | 39 | 1 d | `icon_tag` (14), `closable_data` (5), `draggable_class?` (3), `guest_accessible_icon_tag` (3), `figure_out_target_section` (3). Lowest-coverage helper in the codebase. `figure_out_target_section` is real logic, not markup. |
| 38 | `application_helper.rb` (74%) | 28 | 1 d | `link_to_check_all` (5), `link_to_uncheck_all` (5), `searchable_sections` (4), `page_versions` (4), `select_per_page` (2). `test/unit/helpers/application_helper_test.rb` exists. |
| 39 | `content_block_helper.rb` (17%) | 25 | 4 h | `content_block_tr_tag` (17), `block_row_tag` (7). **Note the source comment: `block_row_tag` is marked "Delete once we confirm that content_block_tr_tag below works."** Resolve that question first — you may be able to delete 7 of these 25 lines instead of testing them. |
| 40 | `page_helper.rb` (75%) | 17 | 4 h | `render_portlet` (6), `container_has_block?` (5), `cms_toolbar` (2), `deprecated_set_page_title_usage` (2). |
| 41 | `path_helper.rb` (68%) | 14 | 4 h | `link_to_usages` (11), `link_to_addressable_content` (3). Route-helper generation — **engine route helpers are upgrade-sensitive.** |
| 42 | `template_support.rb` | 18 | 2 h | `self.included` (14). Not a helper — a controller mixin. Covered by including it into a test-only controller. Cheap. |
| 43 | `rendering_helper.rb` (84%), `form_tag_helper.rb` (73%) | 6 + 4 | 3 h | Top-up. |

**Deliberately excluded from Phase 5:** the Devise shim helpers — `app/helpers/cms/sites/devise_shim_helper.rb` (31 counted, ~12 real), plus `app/helpers/login_portlet_helper.rb` (10) and `app/helpers/forgot_password_portlet_helper.rb` (9), both of which sit at the top of `app/helpers/`, outside the `cms/` namespace. These exist purely to fake a Devise mapping inside a portlet's view context; `devise_shim_helper.rb` contains a `main_app` method whose entire body is commented out. Testing them means reconstructing Devise's controller/mapping context by hand for ~25 real lines of shim. **Poor value — and they may not survive the upgrade anyway.** Revisit after Devise is upgraded.

### Phase 6 — Long tail (~4 days, → 93.2%)

| Rank | Target | Missed | Effort | Notes |
|---|---|---|---|---|
| 44 | `lib/cms/behaviors/attaching.rb` (83%) | 26 | 1 d | `validates_attachment_size` (9), `validates_attachment_content_type` (6), `validates_attachment_presence` (3). Three validation macros, zero coverage between them. `test/unit/behaviors/attaching_test.rb` exists. **Validation macro internals are a Rails 8 risk area.** Note before starting: `validates_attachment_presence` is **defined twice**, at lines 89 and 98 — the first is dead code silently overwritten by the second. Delete one, then test. |
| 45 | `app/portlets/list_portlet.rb` (36%) | 14 | 4 h | `render` (8), `view_as_full_path` (3). `test/unit/portlets/list_portlet_test.rb` exists. |
| 46 | `app/portlets/email_page_portlet.rb` (26%) | 14 | 4 h | `deliver` (9), `render` (4). Needs `ActionMailer::Base.deliveries` assertions; `test/unit/models/email_page_portlet_test.rb` exists. `features/portlets/email_friend_portlet.feature` also exists — check why it isn't reaching `deliver`. |
| 47 | `app/inputs/attachments_input.rb` (0%) | 14 | 4 h | `input` (12). SimpleForm custom input. `spec/inputs/name_input_spec.rb` is the pattern. |
| 48 | `lib/cms/authentication/controller.rb` (68%) | 11 | 4 h | `access_denied` (4), `logout_keeping_session!` (3), `logout_killing_session!` (2). **Session-reset semantics change across Rails versions** — worth more than 11 lines suggests. |
| 49 | `lib/cms/mobile_aware.rb` (73%) | 9 | 2 h | `print_request_info` (7) — a debug method. Consider deleting instead. |
| 50 | `app/inputs/cms_text_area_input.rb`, `file_picker_input.rb`, `name_input.rb`, `app/portlets/helpers/cms/list_portlet_helper.rb` | ~20 | 1 d | Small SimpleForm inputs. |
| 51 | `lib/cms/form_builder/deprecated_inputs.rb` (45%) | 12 | 3 h | Six methods, 2 missed lines each — a uniform deprecation-warning pattern. One shared test loop covers all six. |
| 52 | `content_rendering_support.rb` (86%), `archiving.rb` (80%), `content_block_form_builder.rb` (56%) | 8+6+7 | 1 d | Top-up. |

### Phase 7 — In-process generator tests (~3 days)

Only if §0c is decided in favour of testing rather than excluding. Use `Rails::Generators::TestCase`; `test_helper.rb` is already set up for it.

Do this one regardless of the coverage decision:

> `content_block_generator.rb:27` calls `File.exists?`, which was deprecated in Ruby 2.1 and **removed**. `alter_the_migration` (30 missed lines) is the single largest untested method in the codebase and does text surgery on generated migration files. Nothing in the measured suite touches either.

`install_generator.rb` (16) and `browser_cms.rb` (12) are nearly free — mostly class body, covered by loading.

---

## 4. What is not worth testing

Being explicit about the ceiling, since the question was whether 100% is feasible. **It is not, and chasing it would waste weeks.**

| Target | Missed | Why we stop |
|---|---|---|
| `lib/generators/.../demo.seeds.rb` | 249 | Generator template. Executed only inside a generated app, by design. Filter it. |
| `lib/cms/commands/actions.rb` | 33 | `run_bundle_install`, `run_bundle_update`, `generate_installation_script`, `find_custom_blocks` — shells out to Bundler and writes files to disk. `test/unit/lib/cms/commands_actions_test.rb` already covers the 39% that is testable. The rest belongs to the aruba `@cli` features and should stay there. |
| Devise shim helpers | ~50 counted / ~25 real | See Phase 5 note. Reconstructing Devise's mapping context by hand is more code than the shims contain. |
| `lib/templates/`, `lib/generators/**/templates/` | 34 | Same as `demo.seeds.rb`. |
| Error/rescue branches throughout | ~100 | `rescue` bodies that log and re-raise. Testable, but each one costs a mock and buys one line. |
| `print_request_info`, `log_update` | ~10 | Debug logging. |

Realistic ceiling on the **filtered** denominator (~5,980 lines): **92–93%.** On the raw 6,743-line denominator as the report reads today: **~85%.** Anything past that is error branches, shell-outs, and Devise scaffolding.

---

## 5. Recommended sequencing against the Rails 8 upgrade

Coverage-per-effort ordering (Phases 1→6) and upgrade-risk ordering are not the same, and the difference matters. Three items are cheap *and* sit directly on the upgrade blast radius. **Pull them forward regardless of their rank:**

1. **#17 `form_fields_controller.rb`** — mutates `ActionController::Parameters` in place (`params[:form_field].delete(:form_id)`). Will break.
2. **#19 `page_route_options_controller.rb`** — `update_attributes`, removed in Rails 7. Will break.
3. **#21 `page_components_controller.rb`** — `respond_with`, extracted from core. Will break.

And two are cheap and sit on a security boundary rather than an upgrade one:

4. **#20 `portlet_controller.rb#execute_handler`** — untested `send(params[:handler])` dispatch guard.
5. **#3 `cms_user.rb#able_to_view?`** — untested permission check.

Suggested order: **Phase 0 → items 1–5 above → Phase 1 → Phase 2 → Phase 3 → begin the upgrade → Phases 4–6 as regression pressure demands.**

Add a coverage floor to CI once Phase 0 lands so the number cannot regress silently:

```ruby
SimpleCov.minimum_coverage 78
```

Raise it at the end of each phase. Two caveats: `.travis.yml` is dead and there is no `.github/workflows/` in this repo, so the floor is only meaningful once CI exists to enforce it; and `simplecov` is pinned at **0.12.0** (2016), which has no branch coverage — so every figure in this document is *line* coverage only. Bumping SimpleCov to a version with `enable_coverage :branch` would be worth doing early, because branch coverage on the controllers is the number that actually predicts upgrade breakage, and it will read considerably lower than 72%.

---

## Appendix — reproducing these numbers

```bash
bundle exec rake test        # runs units, spec, functionals, features; writes coverage/
open coverage/index.html
```

Per-file and per-method figures in this document were extracted from `coverage/index.html` (the authoritative merged report) rather than from `coverage/.resultset.json`. The raw resultset stores per-suite arrays in which a file never loaded by a given suite appears with every line marked `0`; naively unioning the four suites overstates missed lines by roughly 3× on files like `content_block_controller.rb` (206 vs. the true 30).
