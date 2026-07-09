class ExperimentsController < ApplicationController
  before_action :set_site
  before_action :require_editor!

  def create
    recommendation = @site.recommendations.find(params[:recommendation_id])
    lifecycle.launch_from_recommendation!(site: @site, recommendation:, user: current_user, account: current_account)
    redirect_to site_with_selected_section(recommendation.section_id), notice: "实验已启动。"
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(recommendation.section_id), alert: error.message
  end

  def pause
    experiment = @site.experiments.find(params[:id])
    lifecycle.pause!(experiment:, user: current_user, account: current_account)
    redirect_to site_with_selected_section(experiment.section_id), notice: "实验已暂停。"
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(experiment.section_id), alert: error.message
  end

  def resume
    experiment = @site.experiments.find(params[:id])
    lifecycle.resume!(experiment:, user: current_user, account: current_account)
    redirect_to site_with_selected_section(experiment.section_id), notice: "实验已继续。"
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(experiment.section_id), alert: error.message
  end

  def complete
    experiment = @site.experiments.find(params[:id])
    lifecycle.complete!(experiment:, user: current_user, account: current_account)
    redirect_to site_with_selected_section(experiment.section_id), notice: "实验已完成。"
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(experiment.section_id), alert: error.message
  end

  def apply_winner
    experiment = @site.experiments.find(params[:id])
    variant = experiment.variants.find(params[:variant_id])
    lifecycle.apply_winner!(experiment:, variant:, user: current_user, account: current_account)
    redirect_to site_with_selected_section(experiment.section_id), notice: "胜出版本已应用。"
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(experiment.section_id), alert: error.message
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end

  def lifecycle
    @lifecycle ||= Experiments::LifecycleService.new
  end

  def site_with_selected_section(section_id)
    site_path(@site, selected_section_id: section_id)
  end
end
