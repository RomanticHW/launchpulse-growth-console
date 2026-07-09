# Review Hardening PR Stack Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the high-priority correctness and multi-tenant gaps found in the LaunchPulse review, then add production-demo hardening, without turning the project into a full SaaS.

**Architecture:** Seven stacked PRs ordered by risk and dependency. Each PR is independently shippable (tests green + docs updated). Correctness/data invariants land first (slug, attribution, locks); production defaults and tooling follow. Prefer minimal code changes that extend existing scopes/services rather than new frameworks.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec, Solid Queue, existing service objects under `app/services/`.

**Source review priorities:** global public slug, pause/complete attribution, lifecycle row locks, production TLS/CSP/hosts, rate limit + RBAC, summary/broadcast consistency, publish lock + CI alignment.

---

## PR Stack Overview

| PR | Branch suggestion | Theme | Risk if skipped |
|----|-------------------|--------|-----------------|
| **PR1** | `fix/public-slug-global-unique` | Public slug multi-tenant correctness | Wrong site / ambiguous public URL |
| **PR2** | `fix/attribution-after-pause` | Conversion attribution after pause/complete | Lost late conversions |
| **PR3** | `fix/lifecycle-row-locks` | Experiment transition concurrency | Double-apply winner / bad status |
| **PR4** | `fix/publish-version-lock` | Publish version race + rollback guard | Failed publish / broken experiments |
| **PR5** | `fix/summary-broadcast-durability` | Metrics window + dashboard refresh | Stale/inconsistent dashboard |
| **PR6** | `chore/production-hardening-basics` | TLS, cookies, session, hosts, CSP | Production misconfig |
| **PR7** | `chore/rbac-rate-limit-ci` | Roles, throttle, `bin/ci` + auth specs | Demo abuse / CI confusion |

**Dependency graph:**

```text
PR1 ──┐
PR2 ──┼──► PR3 ──► PR4 ──► PR5 ──► PR6 ──► PR7
      │
      └── (PR1/PR2 independent; implement either order)
```

**Out of scope (explicit YAGNI):** real payment, external LLM, full stats platform, multi-account switcher UI, importmap overhaul, UI redesign.

**Verification after every PR:**

```bash
cd /Users/huangwei/Rom/Strikingly
bundle exec rspec
# Optional fuller gate:
bin/check-demo
```

---

## File Map (all PRs)

| Area | Primary files |
|------|----------------|
| Public slug | `app/models/site.rb`, `app/controllers/public/base_controller.rb`, migration, `db/seeds.rb`, `spec/requests/public_sites_spec.rb`, `spec/models/site_spec.rb` |
| Attribution | `app/models/experiment.rb`, `app/services/analytics/aggregation_service.rb`, `app/controllers/public/base_controller.rb`, `app/services/events/ingestion_service.rb`, `spec/services/analytics/aggregation_service_spec.rb`, `spec/requests/public_forms_and_checkout_spec.rb` |
| Lifecycle locks | `app/services/experiments/lifecycle_service.rb`, `spec/services/experiments/lifecycle_service_spec.rb`, `spec/requests/experiments_spec.rb` |
| Publish | `app/services/sites/snapshot_service.rb`, `spec/services/sites/snapshot_service_spec.rb`, `spec/requests/publishing_spec.rb` |
| Summary/broadcast | `app/services/analytics/summary_service.rb`, `app/services/analytics/dashboard_broadcaster.rb`, `app/jobs/*` (optional trailing job), specs under `spec/services/analytics/` |
| Production | `config/environments/production.rb`, `config/initializers/content_security_policy.rb`, `app/controllers/sessions_controller.rb`, `app/controllers/public/base_controller.rb`, `app/models/user.rb` |
| RBAC / rate limit / CI | `app/controllers/application_controller.rb`, console controllers, `Gemfile`, rack-attack initializer, `config/ci.rb`, `readme/07-running-and-quality.md`, `readme/08-limitations-and-roadmap.md` |

---

## PR1: Global public slug uniqueness

**Goal:** Public route `Site.find_by!(slug:, status: "published")` cannot resolve the wrong tenant.

### Task 1.1: Failing tests for slug uniqueness + public resolution

**Files:**
- Modify: `spec/models/site_spec.rb`
- Modify: `spec/requests/public_sites_spec.rb`
- Create if needed: migration test is covered by model uniqueness + request

- [ ] **Step 1: Write failing model uniqueness example**

```ruby
# spec/models/site_spec.rb
it "enforces slug uniqueness globally, not only per account" do
  create(:site, account: create(:account), slug: "shared-shop")
  other = build(:site, account: create(:account), slug: "shared-shop")

  expect(other).not_to be_valid
  expect(other.errors[:slug]).to be_present
end
```

- [ ] **Step 2: Write failing public collision example**

```ruby
# spec/requests/public_sites_spec.rb
it "serves the single published site for a slug without tenant collision" do
  account_a = create(:account)
  account_b = create(:account)
  site_a = create(:site, account: account_a, slug: "collision-slug", status: "published")
  # After fix: second site with same slug must be invalid / raise on create.
  # Before fix: this may succeed and make find_by non-deterministic.
  expect {
    create(:site, account: account_b, slug: "collision-slug", status: "published")
  }.to raise_error(ActiveRecord::RecordInvalid)
end
```

- [ ] **Step 3: Run tests — expect FAIL**

```bash
bundle exec rspec spec/models/site_spec.rb spec/requests/public_sites_spec.rb
```

### Task 1.2: Migration + model validation

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_make_site_slugs_globally_unique.rb`
- Modify: `app/models/site.rb` (uniqueness scope)
- Modify: `db/seeds.rb` only if seed slugs could collide (they currently use distinct slugs — verify)

- [ ] **Step 1: Add migration**

```ruby
class MakeSiteSlugsGloballyUnique < ActiveRecord::Migration[8.1]
  def up
    # Demo data should already have unique slugs; fail loudly if not.
    duplicates = select_all(<<~SQL.squish).to_a
      SELECT slug, COUNT(*) AS c FROM sites GROUP BY slug HAVING COUNT(*) > 1
    SQL
    raise "Duplicate site slugs exist: #{duplicates.inspect}" if duplicates.any?

    remove_index :sites, name: "index_sites_on_account_id_and_slug" if index_exists?(:sites, %i[account_id slug], name: "index_sites_on_account_id_and_slug")
    add_index :sites, :slug, unique: true, name: "index_sites_on_slug"
  end

  def down
    remove_index :sites, name: "index_sites_on_slug" if index_exists?(:sites, :slug, name: "index_sites_on_slug")
    add_index :sites, %i[account_id slug], unique: true, name: "index_sites_on_account_id_and_slug"
  end
end
```

- [ ] **Step 2: Change model validation**

In `app/models/site.rb`, replace:

```ruby
validates :slug, uniqueness: { scope: :account_id }, format: { with: /\A[a-z0-9-]+\z/ }
```

with:

```ruby
validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
```

- [ ] **Step 3: Migrate + pass tests**

```bash
bin/rails db:migrate
bundle exec rspec spec/models/site_spec.rb spec/requests/public_sites_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate db/schema.rb app/models/site.rb spec/models/site_spec.rb spec/requests/public_sites_spec.rb
git commit -m "fix: enforce globally unique public site slugs"
```

### Task 1.3: Docs note

**Files:**
- Modify: `readme/08-limitations-and-roadmap.md` (remove/adjust multi-tenant slug caveat if listed; or document global uniqueness decision)
- Modify: `readme/04-data-model-and-attribution.md` if it says slug is account-scoped

- [ ] **Step 1: Update one sentence in data-model docs** stating public `slug` is globally unique so `/s/:slug` is unambiguous.
- [ ] **Step 2: Commit**

```bash
git commit -am "docs: note global site slug uniqueness for public URLs"
```

**PR1 done when:** migration applied, uniqueness tests green, full `bundle exec rspec` green.

---

## PR2: Attribution after pause/complete

**Product rule (implement exactly):**

| Action | New assignments / new traffic | Existing assignment late conversion |
|--------|-------------------------------|-------------------------------------|
| `active` | Yes | Yes |
| `paused` | **No** new assignments | **Yes** attribute conversion if assignment already exists |
| `completed` + winner not applied | **No** new assignments | **Yes** if assignment exists (window still open until winner applied OR until `ended_at` — pick **until winner applied or status completed with existing assignment**) |
| `completed` + winner applied | No | No (experiment resolved) |

**Recommended concrete rule (simpler, testable):**

1. **New assignment / public variant serving:** only `status == "active"`.
2. **Conversion attribution (aggregation + stamping on form/checkout events):** allow experiments that are `active` OR (`paused`/`completed` with existing assignment for visitor and `winner_applied_at` nil). Prefer stamping `experiment_id`/`variant_id` on the event at write time from existing assignment.

### Task 2.1: Experiment scopes

**Files:**
- Modify: `app/models/experiment.rb`
- Modify: `spec/models/domain_integrity_spec.rb` or add scope examples

- [ ] **Step 1: Add scopes**

```ruby
# app/models/experiment.rb
scope :active, -> { where(status: "active") }
scope :accepting_new_assignments, -> { where(status: "active") }
scope :open_for_conversion, -> {
  where(status: %w[active paused completed], winner_applied_at: nil)
}
```

- [ ] **Step 2: Spec**

```ruby
it "open_for_conversion includes paused experiments without winner" do
  site = create(:site)
  paused = create(:experiment, site:, status: "paused", winner_applied_at: nil)
  applied = create(:experiment, site:, status: "completed", winner_applied_at: Time.current)
  expect(site.experiments.open_for_conversion).to include(paused)
  expect(site.experiments.open_for_conversion).not_to include(applied)
end
```

### Task 2.2: Aggregation uses open_for_conversion + existing assignment only

**Files:**
- Modify: `app/services/analytics/aggregation_service.rb`
- Modify: `spec/services/analytics/aggregation_service_spec.rb`

- [ ] **Step 1: Failing aggregation examples**

```ruby
it "attributes form_submit conversion when experiment is paused but assignment exists" do
  site = create(:site)
  page = create(:page, site:)
  section = create(:section, page:)
  experiment = create(:experiment, site:, section:, status: "paused", primary_goal: "form_submit")
  variant = create(:variant, experiment:)
  assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
  event = site.events.create!(
    event_type: "form_submit",
    visitor_id: "visitor-1",
    source: "direct",
    device: "desktop",
    metadata: { "section_uid" => section.uid },
    occurred_at: Time.current
  )

  described_class.new(event).call

  expect(assignment.conversions.where(conversion_type: "form_submit").count).to eq(1)
end

it "does not attribute conversion after winner is applied" do
  site = create(:site)
  page = create(:page, site:)
  section = create(:section, page:)
  experiment = create(:experiment, site:, section:, status: "completed", winner_applied_at: Time.current, primary_goal: "form_submit")
  variant = create(:variant, experiment:)
  assignment = experiment.assignments.create!(visitor_id: "visitor-1", variant:)
  event = site.events.create!(
    event_type: "form_submit",
    visitor_id: "visitor-1",
    source: "direct",
    device: "desktop",
    metadata: { "section_uid" => section.uid },
    occurred_at: Time.current
  )

  described_class.new(event).call

  expect(assignment.conversions.count).to eq(0)
end

it "does not create a new assignment during aggregation for paused experiments" do
  site = create(:site)
  page = create(:page, site:)
  section = create(:section, page:)
  experiment = create(:experiment, site:, section:, status: "paused", primary_goal: "form_submit")
  create(:variant, experiment:)
  event = site.events.create!(
    event_type: "form_submit",
    visitor_id: "visitor-new",
    source: "direct",
    device: "desktop",
    metadata: { "section_uid" => section.uid },
    occurred_at: Time.current
  )

  described_class.new(event).call

  expect(experiment.assignments.where(visitor_id: "visitor-new")).to be_empty
  expect(experiment.conversions).to be_empty
end
```

- [ ] **Step 2: Run — expect FAIL**

```bash
bundle exec rspec spec/services/analytics/aggregation_service_spec.rb
```

- [ ] **Step 3: Implement**

In `section_assignment_for_event` and `generic_assignments_for_event`, replace `.active` with `.open_for_conversion`, and **never** call `create_or_find_by!` for non-active experiments (only look up existing assignments when status != active).

Suggested shape for `assignment_for`:

```ruby
def assignment_for(experiment)
  assignment = experiment.assignments.find_by(visitor_id: @event.visitor_id)
  return matching_assignment_or_nil(assignment) if assignment
  return nil unless experiment.active?
  return nil unless @event.experiment_id == experiment.id && @event.variant

  experiment.assignments.create_or_find_by!(visitor_id: @event.visitor_id) do |record|
    record.variant = @event.variant
  end
rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
  matching_assignment_or_nil(experiment.assignments.find_by!(visitor_id: @event.visitor_id))
end
```

And section lookup:

```ruby
experiment = @site.experiments.open_for_conversion.joins(:section).find_by(sections: { uid: section_uid })
```

- [ ] **Step 4: Pass aggregation specs**

### Task 2.3: Public form/checkout stamp assignment from history when paused

**Files:**
- Modify: `app/controllers/public/base_controller.rb` (`assignment_for_section_uid`)
- Modify: `app/services/events/ingestion_service.rb` (section path: no **new** assign if not active; if paused/completed with existing assignment, use it for attribution on conversion events only — keep API explicit path strict)
- Modify: `spec/requests/public_forms_and_checkout_spec.rb`

**Rule for public runtime:**

- `assignment_map` / rendering variants: **active only** (visitor should not keep seeing frozen variant after pause if product says pause = stop test traffic — current UI already uses active; keep it).
- `assignment_for_section_uid` used by form/checkout: if active → assign as today; if not active → `find_by(visitor_id:)` only on `open_for_conversion` experiments for that section.

```ruby
def assignment_for_section_uid(site, section_uid, require_visible: false)
  return nil if section_uid.blank?
  raise HiddenSectionError, "Section is not visible" if require_visible && !section_uid_visible?(site, section_uid)

  experiment = site.experiments.accepting_new_assignments.joins(:section).find_by(sections: { uid: section_uid })
  if experiment
    return Experiments::AssignmentService.new(experiment).assign(visitor_id)
  end

  # Late conversion path: paused/completed unresolved experiments keep historical assignment.
  experiment = site.experiments.open_for_conversion.joins(:section).find_by(sections: { uid: section_uid })
  return nil unless experiment

  experiment.assignments.find_by(visitor_id: visitor_id)
end
```

- [ ] **Step 1: Request spec** — pause experiment, visitor already assigned, submit form, expect conversion after aggregation job/inline call.
- [ ] **Step 2: Implement + green**
- [ ] **Step 3: Commit**

```bash
git add app/models/experiment.rb app/services/analytics/aggregation_service.rb \
  app/controllers/public/base_controller.rb app/services/events/ingestion_service.rb \
  spec/
git commit -m "fix: attribute conversions for paused experiments with existing assignments"
```

**IngestionService note:** Keep **new** section assignment only for `.active`. Do **not** expand PR2 into full API conversion-stamping redesign — public form/checkout + aggregation is enough for the product rule. Do not allow client to force a new assignment on paused experiments.

**PR2 done when:** aggregation + public form/checkout specs cover pause path; full suite green.

---

## PR3: Lifecycle row locks

**Goal:** All status transitions and `apply_winner!` are serialized on the experiment row.

### Task 3.1: Failing concurrency / double-apply specs

**Files:**
- Modify: `spec/services/experiments/lifecycle_service_spec.rb`

- [ ] **Step 1: Add examples**

```ruby
it "rejects a second apply_winner! after the first succeeds" do
  # complete experiment, apply control, second apply variant raises InvalidTransition
end

it "does not allow pause after complete" do
  service.complete!(...)
  expect { service.pause!(...) }.to raise_error(Experiments::LifecycleService::InvalidTransition)
end
```

Optional stress (if reliable in CI):

```ruby
it "serializes concurrent apply_winner! so only one mutates section props" do
  # Use threads only if DB allows; otherwise document as best-effort and rely on lock + re-check
end
```

### Task 3.2: Implement locked transitions

**Files:**
- Modify: `app/services/experiments/lifecycle_service.rb`

- [ ] **Step 1: Wrap mutations**

```ruby
def pause!(experiment:, user:, account:)
  experiment.with_lock do
    require_status!(experiment, "active", action: "pause")
    transition!(experiment:, status: "paused", user:, account:, action: "experiment_paused")
  end
end

def resume!(experiment:, user:, account:)
  experiment.with_lock do
    require_status!(experiment, "paused", action: "resume")
    transition!(experiment:, status: "active", user:, account:, action: "experiment_resumed", ended_at: nil)
  end
end

def complete!(experiment:, user:, account:)
  experiment.with_lock do
    unless %w[active paused].include?(experiment.status)
      raise InvalidTransition, "只有运行中或已暂停的实验可以完成。"
    end
    # existing updates...
  end
end

def apply_winner!(experiment:, variant:, user:, account:)
  experiment.with_lock do
    raise InvalidTransition, "请先完成实验，再应用胜出版本。" unless experiment.status == "completed"
    raise InvalidTransition, "胜出版本已经应用过。" if experiment.winner_applied_at.present?
    raise InvalidTransition, "该版本不属于当前实验。" if variant.experiment_id != experiment.id
    # existing transaction body — with_lock already opens a transaction in Rails
    experiment.section.update!(props: variant.props)
    experiment.update!(winner_variant: variant, winner_applied_at: Time.current)
    # mark control/recommended...
  end
end
```

**Notes:**
- `with_lock` reloads the row — re-check status **inside** the block (do not use stale in-memory status).
- Nested `ActiveRecord::Base.transaction` inside `with_lock` is OK but can be simplified to a single locked block.
- Keep `section.with_lock` on launch as-is.

- [ ] **Step 2: Green specs + commit**

```bash
bundle exec rspec spec/services/experiments/lifecycle_service_spec.rb spec/requests/experiments_spec.rb
git commit -am "fix: lock experiment rows during lifecycle transitions"
```

**PR3 done when:** double-apply and illegal transitions covered; suite green.

---

## PR4: Publish version lock + rollback guard

### Task 4.1: Site-locked publish version allocation

**Files:**
- Modify: `app/services/sites/snapshot_service.rb`
- Modify: `spec/services/sites/snapshot_service_spec.rb`

- [ ] **Step 1: Failing test** — two sequential publishes get versions N and N+1; optional: assert version uniqueness under lock (hard to race in single process — test that `publish!` uses site lock by stubbing or by documenting with sequential multi-thread if reliable).

Minimum test:

```ruby
it "allocates monotonically increasing versions for sequential publishes" do
  site = create(:site)
  user = create(:user)
  create(:page, site:)
  v1 = described_class.new(site).publish!(user:)
  v2 = described_class.new(site).publish!(user:)
  expect(v2.version).to eq(v1.version + 1)
end
```

- [ ] **Step 2: Implement**

```ruby
def publish!(user:, note: nil)
  @site.with_lock do
    version = @site.published_snapshots.maximum(:version).to_i + 1
    payload = payload_for(@site)
    @site.update!(status: "published")
    @site.published_snapshots.create!(
      version:,
      published_by: user,
      note:,
      payload:,
      checksum: checksum_for(payload),
      published_at: Time.current
    )
  end
end
```

### Task 4.2: Block rollback while unresolved experiments exist

**Files:**
- Modify: `app/services/sites/snapshot_service.rb`
- Modify: `app/controllers/publishing_controller.rb` (surface error)
- Modify: `spec/services/sites/snapshot_service_spec.rb`, `spec/requests/publishing_spec.rb`

- [ ] **Step 1: Failing test**

```ruby
it "refuses rollback when the site has an unresolved experiment" do
  # create active experiment on a section, attempt rollback!, expect error
end
```

- [ ] **Step 2: Implement**

```ruby
class UnresolvedExperiments < StandardError; end

def rollback!(snapshot, user:)
  verify_checksum!(snapshot)
  if unresolved_experiments?
    raise UnresolvedExperiments, "请先结束并应用实验胜出版本，再回滚发布。"
  end
  # existing body...
end

def unresolved_experiments?
  @site.experiments.where(status: %w[active paused]).exists? ||
    @site.experiments.where(status: "completed", winner_applied_at: nil).exists?
end
```

- [ ] **Step 3: Controller rescue → flash/redirect**
- [ ] **Step 4: Commit**

```bash
git commit -am "fix: lock publish versions and block rollback during open experiments"
```

**PR4 done when:** publish/rollback specs green; suite green.

---

## PR5: Summary window consistency + broadcast durability

### Task 5.1: Align SummaryService time windows

**Files:**
- Modify: `app/services/analytics/summary_service.rb`
- Modify: `spec/services/analytics/summary_service_spec.rb`

**Decision (simple, documented):** Normalize `@since` to beginning of day in the app time zone so rollup `bucket_date` and raw `occurred_at` windows match calendar days.

```ruby
def initialize(site, since: 14.days.ago)
  @site = site
  @since = since.in_time_zone.beginning_of_day
  @events = site.events.where(occurred_at: @since..)
end
```

- [ ] **Step 1: Spec** — events on boundary day count once consistently for page_views path.
- [ ] **Step 2: Implement + green**

### Task 5.2: Trailing dashboard refresh after throttle

**Files:**
- Modify: `app/services/analytics/dashboard_broadcaster.rb`
- Create (optional): `app/jobs/dashboard_refresh_job.rb`
- Modify: `spec/services/analytics/dashboard_broadcaster_spec.rb`

**Minimal approach (prefer):** After leading-edge throttle skip, schedule a single delayed job if none pending:

```ruby
# In broadcast_summary when cache hit (throttled):
DashboardRefreshJob.set(wait: THROTTLE).perform_later(site.id) if cache.write("dashboard-refresh-scheduled:#{site.id}", true, expires_in: THROTTLE, unless_exist: true)
```

Job clears flag and calls `DashboardBroadcaster.new(site).broadcast_summary(force: true)`.

**API change required:** `broadcast_summary` currently has no `force:` kwarg. Add `force: false` and when `force` is true, **bypass** the leading-edge throttle (`claim_broadcast_slot` / `unless_exist` cache) so the delayed job does not no-op under the same throttle key.

- [ ] **Step 1: Spec that second event within throttle still results in a later refresh** (use ActiveJob test adapter + travel).
- [ ] **Step 2: Implement `force:` + trailing job**
- [ ] **Step 3: Commit**

```bash
git commit -am "fix: align analytics day windows and trailing dashboard broadcast"
```

**Optional small add in same PR:** partial index migration

```ruby
add_index :events, :aggregated_at, where: "aggregated_at IS NULL", name: "index_events_unaggregated"
```

**PR5 done when:** analytics specs green; suite green.

---

## PR6: Production hardening basics

**Still demo-safe:** defaults enable safe production flags; CSP can start report-only or minimal.

### Task 6.1: production.rb + cookies + session fixation

**Files:**
- Modify: `config/environments/production.rb`
- Modify: `app/controllers/sessions_controller.rb`
- Modify: `app/controllers/public/base_controller.rb`
- Modify: `app/models/user.rb` (min password length)
- Modify: `spec/requests/` for sessions if present; else add `spec/requests/sessions_spec.rb`

- [ ] **Step 1: Enable**

```ruby
# config/environments/production.rb
config.assume_ssl = true
config.force_ssl = true
config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
config.hosts.clear # then add from ENV
# Prefer:
# config.hosts << ENV.fetch("APP_HOST") if ENV["APP_HOST"].present?
```

If `APP_HOST` is optional for demo deploys, document required env in `readme/07-running-and-quality.md`.

- [ ] **Step 2: Session fixation fix**

```ruby
# sessions_controller.rb create
if user&.authenticate(params[:password])
  reset_session
  session[:user_id] = user.id
  redirect_to root_path
end
```

- [ ] **Step 3: Secure visitor cookies in production**

```ruby
cookies.signed[:launch_pulse_visitor_id] = {
  value: generated,
  expires: 1.year.from_now,
  httponly: true,
  same_site: :lax,
  secure: Rails.env.production?
}
```

Same for session cookie.

- [ ] **Step 4: Password minimum**

```ruby
# user.rb
validates :password, length: { minimum: 8 }, if: -> { password.present? }
```

Demo password `"password"` is already 8 chars — **no mass fixture rewrite** unless length rule is raised above 8.

- [ ] **Step 5: CSP** — enable report-only or basic policy in `config/initializers/content_security_policy.rb` compatible with importmap + tailwind (self + nonces if already used). If CSP breaks Stimulus without nonces, use report-only first:

```ruby
Rails.application.configure do
  config.content_security_policy_report_only = true
  # policy.default_src :self
  # policy.script_src  :self
  # ...
end
```

- [ ] **Step 6: Specs for reset_session (optional rack session id change) + password validation**
- [ ] **Step 7: Commit**

```bash
git commit -am "chore: enable production SSL defaults, secure cookies, and session fixation fix"
```

**PR6 done when:** suite green; docs mention `APP_HOST` / SSL assumptions.

---

## PR7: RBAC, rate limiting, CI alignment

### Task 7.1: Minimal membership authorization

**Files:**
- Modify: `app/controllers/application_controller.rb`
- Modify: write controllers (publish, experiments apply, simulations, sites token rotate, section patches apply)
- Create: `spec/requests/authorization_spec.rb`

**Policy (minimal):**

| Role | Read dashboard/sites | Mutate content / experiments / publish / patches / AI audit | Simulate traffic | Rotate API token |
|------|----------------------|-------------------------------------------------------------|------------------|------------------|
| owner | yes | yes | yes | yes |
| marketer | yes | yes (incl. `ai_audits#create`, experiment pause/resume/complete/apply/create, section patches) | no | no |
| viewer | yes | no | no | no |

Wire `require_role!` on **all** mutating console actions (not only publish): experiments, section_patches, publishing, ai_audits, simulations, sites token rotate.

```ruby
# application_controller.rb
def current_membership
  @current_membership ||= current_user.memberships.find_by(account: current_account)
end

def require_role!(*roles)
  return if current_membership && roles.include?(current_membership.role)

  redirect_to root_path, alert: "没有权限执行这个操作。"
end
```

Apply `before_action` on mutating actions only. Default memberships in seeds/factories stay `owner` so existing specs pass.

- [ ] **Step 1: Factory helper** `create(:membership, role: "viewer")`
- [ ] **Step 2: Authorization request specs** (viewer cannot POST publish; owner can)
- [ ] **Step 3: Cross-account IDOR smoke**

```ruby
it "does not allow user A to publish user B site by id" do
  # sign in A, post publish for B.site id -> 404
end
```

### Task 7.2: Rack::Attack throttles

**Files:**
- Modify: `Gemfile` (+ `Gemfile.lock` via bundle)
- Create: `config/initializers/rack_attack.rb`
- Modify: `spec/` optional request throttle (can be light)

Throttle (start conservative for demo):

| Path | Limit |
|------|-------|
| `POST /session` | 10 / min / IP |
| `POST /s/*/events` | 120 / min / IP |
| `POST /api/v1/events` | 300 / min / IP+token |
| `POST` checkout/forms | 30 / min / IP |

- [ ] **Step 1: Add gem `rack-attack`**
- [ ] **Step 2: Initializer using Rails cache**
- [ ] **Step 3: Document in `readme/07` and limitations**

### Task 7.3: bin/ci runs RSpec

**Files:**
- Modify: `config/ci.rb`
- Modify: `readme/07-running-and-quality.md`

```ruby
# config/ci.rb — add after setup, before or after style:
step "Tests: RSpec", "bundle exec rspec"
```

Note: GitHub already uses `bin/check-demo`. Local `bin/ci` should not surprise reviewers by skipping tests.

- [ ] **Step 1: Add RSpec step**
- [ ] **Step 2: Doc one paragraph: `bin/ci` (lint+security+tests) vs `bin/check-demo` (tests+zeitwerk+tailwind+package)**
- [ ] **Step 3: Full suite + commit**

```bash
bundle exec rspec
git commit -am "chore: enforce RBAC, rate limits, and RSpec in bin/ci"
```

**PR7 done when:** authorization specs green; full suite green; docs updated.

---

## Execution Checklist (orchestrator)

For each PR 1→7:

1. Create branch from previous PR tip (or `main` if stacking later).
2. TDD: failing test → implement → green.
3. Run `bundle exec rspec` (full).
4. Commit with conventional message above.
5. Open PR with body:
   - Problem (from review)
   - Solution
   - Test plan
   - Residual risks

**Final merge verification:**

```bash
bin/check-demo
```

Expected: RSpec pass, zeitwerk OK, tailwind build OK, package-demo OK.

---

## Residual risks (do not block this stack)

- Client-controlled `visitor_id` on API still allows experiment skew (document; optional later HMAC).
- API still accepts conversion event types with site token (product decision).
- Confidence intervals remain approximate (already labeled).
- No multi-account switcher (`accounts.first` remains).
- Trailing broadcast is best-effort under multi-process without solid cache shared correctly — Solid Cache is already configured for production.

---

## Suggested PR titles / descriptions (copy-paste)

**PR1**  
Title: `fix: make public site slugs globally unique`  
Body: Public lookup is global; uniqueness was account-scoped. Align DB + validation.

**PR2**  
Title: `fix: credit late conversions for paused experiments`  
Body: Pause stops new assignments; existing visitors still convert against open experiments until winner applied.

**PR3**  
Title: `fix: serialize experiment lifecycle with row locks`  
Body: Prevent concurrent apply_winner / status races.

**PR4**  
Title: `fix: lock publish versions and guard rollback`  
Body: Monotonic version under site lock; block rollback during unresolved experiments.

**PR5**  
Title: `fix: reconcile analytics windows and trailing dashboard refresh`  
Body: Day-boundary alignment + throttle trailing edge.

**PR6**  
Title: `chore: production SSL, secure cookies, session fixation`  
Body: Enable force_ssl defaults, secure visitor cookies, reset_session on login.

**PR7**  
Title: `chore: viewer RBAC, rate limiting, and RSpec in bin/ci`  
Body: Minimal roles, Rack::Attack, CI parity with demo check.

---

## Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-09-review-hardening-prs.md`.

**Ready to execute?** Recommended: start with **PR1** then **PR2** (highest correctness impact, independent), using superpowers:subagent-driven-development or superpowers:executing-plans.
