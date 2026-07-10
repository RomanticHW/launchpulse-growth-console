class SimulationsController < ApplicationController
  before_action :set_site
  before_action :require_owner!

  def create
    TrafficSimulatorJob.perform_later(@site.id, visitors: 1000)
    redirect_to @site, notice: "模拟访问任务已提交，数据将在后台陆续更新。"
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end
end
