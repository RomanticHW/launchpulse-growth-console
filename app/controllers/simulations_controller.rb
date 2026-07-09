class SimulationsController < ApplicationController
  before_action :set_site
  before_action :require_owner!

  def create
    TrafficSimulatorJob.perform_later(@site.id, visitors: 1000)
    redirect_to @site, notice: "访客模拟任务已加入队列。"
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end
end
