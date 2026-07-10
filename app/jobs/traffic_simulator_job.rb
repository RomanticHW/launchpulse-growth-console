class TrafficSimulatorJob < ApplicationJob
  queue_as :default

  SOURCES = %w[direct search social email referral paid].freeze
  DEVICES = %w[desktop mobile mobile tablet].freeze

  def perform(site_id, visitors: 1000)
    site = Site.find(site_id)
    page = site.home_page
    experiments = visible_experiments(site)

    visitors.times do |index|
      visitor_id = "sim-#{Time.current.to_i}-#{index}"
      source = SOURCES.sample
      device = DEVICES.sample
      occurred_at = rand(10.days.to_i).seconds.ago
      assignments = experiments.each_with_object({}) do |experiment, result|
        assignment = Experiments::AssignmentService.new(experiment).assign(visitor_id)
        result[experiment.section.uid] = assignment if assignment
      end
      broadcast_experiment_metrics(site, experiments, index)
      assigned_variants = assignments.values.each_with_object({}) do |assignment, result|
        result[assignment.experiment_id.to_s] = assignment.variant.key
      end

      # page_view 只记录分配结果，不归因到某个实验；真正转化要等到具体 section 行为发生。
      page_view = create_event!(site, page, "page_view", visitor_id, source, device, occurred_at, nil, metadata: { simulated: true, assigned_variants: })
      Analytics::AggregationService.new(page_view).call

      next unless rand < 0.42

      cta_assignment = assignment_for_kind(assignments, experiments, "hero")
      cta = create_event!(site, page, "cta_click", visitor_id, source, device, occurred_at + rand(60).seconds, cta_assignment)
      Analytics::AggregationService.new(cta).call

      conversion_assignment = conversion_assignment(assignments, experiments, site)
      conversion_probability = conversion_assignment&.variant&.role == "control" ? 0.11 : 0.18
      next unless rand < conversion_probability

      # 模拟器只生成分析事件流，用来压后台任务和实时看板；真实业务记录由 public form/checkout 入口创建。
      event_type = conversion_assignment&.experiment&.primary_goal || "form_submit"
      event_type = "form_submit" if event_type == "any_conversion"
      conversion = create_event!(site, page, event_type, visitor_id, source, device, occurred_at + rand(180).seconds, conversion_assignment)
      Analytics::AggregationService.new(conversion).call
    end
  end

  private

  def create_event!(site, page, event_type, visitor_id, source, device, occurred_at, assignment, metadata: { simulated: true })
    site.events.create!(
      page:,
      event_type:,
      visitor_id:,
      session_id: "session-#{visitor_id}",
      source:,
      device:,
      experiment: assignment&.experiment,
      variant: assignment&.variant,
      variant_key: assignment&.variant&.key,
      occurred_at:,
      metadata:
    )
  end

  def visible_experiments(site)
    visible_uids = visible_section_uids(site)
    site.experiments.active.includes(:variants, :section).select do |experiment|
      experiment.section && visible_uids.include?(experiment.section.uid)
    end
  end

  def visible_section_uids(site)
    Sites::PublishedRuntime.new(site).visible_section_uids
  end

  def assignment_for_kind(assignments, experiments, kind)
    experiment = experiments.find { |candidate| candidate.section.kind == kind }
    assignments[experiment.section.uid] if experiment
  end

  def conversion_assignment(assignments, experiments, site)
    assignment_for_kind(assignments, experiments, "product_grid") ||
      assignment_for_kind(assignments, experiments, "pricing") ||
      assignment_for_kind(assignments, experiments, "contact_form") ||
      (site.products.exists? ? nil : assignment_for_kind(assignments, experiments, "hero"))
  end

  def broadcast_experiment_metrics(site, experiments, index)
    # visitors 也会影响实验面板，但模拟器不能每个访客都 replace 一次；这里按批次刷新。
    return if experiments.empty?
    return unless (index + 1) % 50 == 0

    Analytics::DashboardBroadcaster.new(site).broadcast_experiments
  end
end
