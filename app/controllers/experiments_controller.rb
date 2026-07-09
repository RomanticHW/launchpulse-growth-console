class ExperimentsController < ApplicationController
  include ExperimentLifecycleResponses

  before_action :set_site
  before_action :require_editor!

  def create
    recommendation = @site.recommendations.find(params[:recommendation_id])
    perform_lifecycle!(recommendation.section_id, notice: "实验已启动。") do
      lifecycle.launch_from_recommendation!(site: @site, recommendation:, user: current_user, account: current_account)
    end
  end

  def pause
    experiment = @site.experiments.find(params[:id])
    perform_lifecycle!(experiment.section_id, notice: "实验已暂停。") do
      lifecycle.pause!(experiment:, user: current_user, account: current_account)
    end
  end

  def resume
    experiment = @site.experiments.find(params[:id])
    perform_lifecycle!(experiment.section_id, notice: "实验已继续。") do
      lifecycle.resume!(experiment:, user: current_user, account: current_account)
    end
  end

  def complete
    experiment = @site.experiments.find(params[:id])
    perform_lifecycle!(experiment.section_id, notice: "实验已完成。") do
      lifecycle.complete!(experiment:, user: current_user, account: current_account)
    end
  end

  def apply_winner
    experiment = @site.experiments.find(params[:id])
    variant = experiment.variants.find(params[:variant_id])
    perform_lifecycle!(experiment.section_id, notice: "胜出版本已应用。") do
      lifecycle.apply_winner!(experiment:, variant:, user: current_user, account: current_account)
    end
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end
end
