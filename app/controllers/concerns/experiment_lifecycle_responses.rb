# Shared redirect + InvalidTransition handling for experiment state changes.
module ExperimentLifecycleResponses
  extend ActiveSupport::Concern

  private

  def lifecycle
    @lifecycle ||= Experiments::LifecycleService.new
  end

  def perform_lifecycle!(section_id, notice:)
    yield
    redirect_to site_with_selected_section(section_id), notice: notice
  rescue Experiments::LifecycleService::InvalidTransition => error
    redirect_to site_with_selected_section(section_id), alert: error.message
  end

  def site_with_selected_section(section_id)
    site_path(@site, selected_section_id: section_id)
  end
end
