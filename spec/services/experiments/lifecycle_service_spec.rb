require "rails_helper"

RSpec.describe Experiments::LifecycleService do
  def recommendation_for(status:)
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title: "Improve CTA",
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8,
      status:,
      suggested_patch: { "cta" => "Get plan" }
    )
    patch_status = status == "applied" ? "applied" : "pending"
    recommendation.create_section_patch!(
      section:,
      status: patch_status,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    [ site, recommendation ]
  end

  def recommendation_for_section(site, section, title:)
    audit = site.ai_audits.create!(status: "completed", score: 70)
    finding = audit.ai_findings.create!(section:, problem: "Weak CTA", severity: "high")
    recommendation = site.recommendations.create!(
      ai_finding: finding,
      section:,
      title:,
      problem: "CTA is too generic",
      expected_impact: "+8%",
      confidence: 0.8,
      suggested_patch: { "cta" => title }
    )
    recommendation.create_section_patch!(
      section:,
      props_diff: recommendation.suggested_patch,
      before_props: section.props,
      after_props: section.props.deep_merge(recommendation.suggested_patch)
    )
    recommendation
  end

  it "rejects direct launch from tested and superseded recommendations" do
    %w[tested superseded testing dismissed].each do |status|
      site, recommendation = recommendation_for(status:)

      expect do
        described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
      end.to raise_error(Experiments::LifecycleService::InvalidTransition)
    end
  end

  it "rejects launch when the caller holds a stale open recommendation" do
    site, recommendation = recommendation_for(status: "open")
    Recommendation.find(recommendation.id).update!(status: "dismissed", dismissed_at: Time.current)

    expect do
      described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition)

    expect(site.experiments).to be_empty
    expect(recommendation.reload.status).to eq("dismissed")
  end

  it "rejects launch when the recommendation section changes before the section lock" do
    site, recommendation = recommendation_for(status: "open")
    replacement_section = create(:section, page: recommendation.section.page, position: 1)

    expect_any_instance_of(Section).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      Recommendation.where(id: recommendation.id).update_all(section_id: replacement_section.id)
      original.call(*args, &block)
    end

    expect do
      described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition, /关联的页面区块已变化/)

    expect(site.experiments).to be_empty
  end

  it "allows applied patch retest only before a winner has been applied" do
    site, recommendation = recommendation_for(status: "applied")
    service = described_class.new

    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    variant = experiment.variants.find_by!(role: "variant")
    service.complete!(experiment:, user: nil, account: site.account)
    service.apply_winner!(experiment:, variant:, user: nil, account: site.account)

    expect do
      service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition)
  end

  it "rejects a second unresolved experiment on the same section" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    first = recommendation_for_section(site, section, title: "First CTA")
    second = recommendation_for_section(site, section, title: "Second CTA")
    service = described_class.new

    service.launch_from_recommendation!(site:, recommendation: first, user: nil, account: site.account)

    expect do
      service.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition, /这个区块已有未结束的实验/)
  end

  it "locks the site before the section while checking and launching an experiment" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    recommendation = recommendation_for_section(site, section, title: "Locked CTA")
    site_lock_held = false

    expect(site).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      original.call(*args) do
        site_lock_held = true
        block.call
      ensure
        site_lock_held = false
      end
    end
    expect_any_instance_of(Section).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      expect(site_lock_held).to be(true)
      original.call(*args, &block)
    end

    experiment = described_class.new.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)

    expect(experiment.section).to eq(section)
  end

  it "treats paused and completed-without-winner experiments as unresolved section tests" do
    %w[paused completed].each do |status|
      site = create(:site)
      page = create(:page, site:)
      section = create(:section, page:)
      first = recommendation_for_section(site, section, title: "First CTA #{status}")
      second = recommendation_for_section(site, section, title: "Second CTA #{status}")
      experiment = create(:experiment, site:, section:, recommendation: first, status:, winner_applied_at: nil)

      expect do
        described_class.new.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)
      end.to raise_error(Experiments::LifecycleService::InvalidTransition)
      expect(experiment.reload.winner_applied_at).to be_nil
    end
  end

  it "allows a new section experiment after the previous winner has been applied" do
    site = create(:site)
    page = create(:page, site:)
    section = create(:section, page:)
    first = recommendation_for_section(site, section, title: "First CTA")
    second = recommendation_for_section(site, section, title: "Second CTA")
    old_experiment = create(:experiment, site:, section:, recommendation: first, status: "completed", winner_applied_at: Time.current)

    new_experiment = described_class.new.launch_from_recommendation!(site:, recommendation: second, user: nil, account: site.account)

    expect(new_experiment.section).to eq(section)
    expect(old_experiment.reload.winner_applied_at).to be_present
  end

  it "rejects a second apply_winner! after the first succeeds" do
    site, recommendation = recommendation_for(status: "open")
    service = described_class.new
    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    control = experiment.variants.find_by!(role: "control")
    variant = experiment.variants.find_by!(role: "variant")
    service.complete!(experiment:, user: nil, account: site.account)
    service.apply_winner!(experiment:, variant: control, user: nil, account: site.account)

    expect do
      service.apply_winner!(experiment:, variant:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition, /已经应用/)
  end

  it "does not allow pause after complete" do
    site, recommendation = recommendation_for(status: "open")
    service = described_class.new
    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    service.complete!(experiment:, user: nil, account: site.account)

    expect do
      service.pause!(experiment:, user: nil, account: site.account)
    end.to raise_error(Experiments::LifecycleService::InvalidTransition)
  end

  it "locks the site before the experiment row while applying a winner" do
    site, recommendation = recommendation_for(status: "open")
    service = described_class.new
    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    variant = experiment.variants.find_by!(role: "variant")
    service.complete!(experiment:, user: nil, account: site.account)
    locked_site = experiment.site
    site_lock_held = false

    expect(locked_site).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      original.call(*args) do
        site_lock_held = true
        block.call
      ensure
        site_lock_held = false
      end
    end
    expect(experiment).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      expect(site_lock_held).to be(true)
      original.call(*args, &block)
    end

    service.apply_winner!(experiment:, variant:, user: nil, account: site.account)
    expect(experiment.reload.winner_applied_at).to be_present
  end

  # Serializes two apply_winner! calls against the same row. Not a load test —
  # it proves the second caller re-reads winner_applied_at under with_lock and
  # loses cleanly instead of double-writing section props.
  it "serializes concurrent apply_winner! so only one mutation wins" do
    site, recommendation = recommendation_for(status: "open")
    service = described_class.new
    experiment = service.launch_from_recommendation!(site:, recommendation:, user: nil, account: site.account)
    control_id = experiment.variants.find_by!(role: "control").id
    variant_id = experiment.variants.find_by!(role: "variant").id
    service.complete!(experiment:, user: nil, account: site.account)

    successes = []
    failures = []
    mutex = Mutex.new
    ready = Queue.new
    go = Queue.new

    threads = [
      [ :control, control_id ],
      [ :variant, variant_id ]
    ].map do |label, id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << label
          go.pop
          begin
            exp = Experiment.find(experiment.id)
            service.apply_winner!(
              experiment: exp,
              variant: exp.variants.find(id),
              user: nil,
              account: site.account
            )
            mutex.synchronize { successes << label }
          rescue Experiments::LifecycleService::InvalidTransition
            mutex.synchronize { failures << label }
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { go << true }
    threads.each(&:join)

    expect(successes.size).to eq(1)
    expect(failures.size).to eq(1)
    expect(experiment.reload.winner_applied_at).to be_present
    expect(experiment.winner_variant_id).to be_in([ control_id, variant_id ])
  end
end
