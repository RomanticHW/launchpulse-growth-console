class SitesController < ApplicationController
  before_action :set_site
  before_action :require_owner!, only: :rotate_tracking_token

  def show
    @summary = Analytics::SummaryService.new(@site).call
    @recommendations = @site.recommendations.includes(:section, :section_patch, :experiments).order(created_at: :desc).limit(6)
    @experiments = @site.experiments.includes(:section, :variants).order(created_at: :desc)
    @experiment_results = Experiments::ResultsCollectionService.new(@experiments).call
    @events = @site.events.recent.limit(25)
    @snapshots = @site.published_snapshots.order(version: :desc)
    @preview_patch = @site.recommendations.find_by(id: params[:preview_recommendation_id])&.section_patch
  end

  def rotate_tracking_token
    @site.api_keys.active.where(name: "Demo tracking token").update_all(active: false, updated_at: Time.current)
    key, raw_token = ApiKey.issue!(site: @site, name: "Demo tracking token")
    flash[:tracking_token] = key.signed_token(raw_token)
    redirect_to @site, notice: "新的追踪令牌已生成，此前的令牌已停用。"
  end

  private

  def set_site
    @site = current_account.sites.find(params[:id] || params[:site_id])
  end
end
