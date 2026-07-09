class DashboardController < ApplicationController
  def index
    @sites = current_account.sites.order(:name)
    @dashboard_summaries = Analytics::DashboardSummaryCollection.new(@sites).call
    @active_experiment_counts = Experiment.where(site_id: @sites.map(&:id), status: "active").group(:site_id).count
  end
end
