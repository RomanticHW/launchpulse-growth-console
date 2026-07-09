class SectionPatchesController < ApplicationController
  before_action :set_site
  before_action :set_patch

  def preview
    redirect_to site_with_selected_section(preview_recommendation_id: @patch.recommendation_id)
  end

  def apply
    @patch.apply!
    AuditLog.create!(account: current_account, user: current_user, site: @site, action: "patch_applied", metadata: { section_patch_id: @patch.id })
    redirect_to site_with_selected_section, notice: "补丁已应用到草稿。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to site_with_selected_section, alert: error.record.errors.full_messages.to_sentence
  end

  def revert
    @patch.revert!
    AuditLog.create!(account: current_account, user: current_user, site: @site, action: "patch_reverted", metadata: { section_patch_id: @patch.id })
    redirect_to site_with_selected_section, notice: "补丁已撤回。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to site_with_selected_section, alert: error.record.errors.full_messages.to_sentence
  end

  def dismiss
    @patch.dismiss!
    AuditLog.create!(account: current_account, user: current_user, site: @site, action: "recommendation_dismissed", metadata: { recommendation_id: @patch.recommendation_id })
    redirect_to site_with_selected_section, notice: "建议已忽略。"
  rescue ActiveRecord::RecordInvalid => error
    redirect_to site_with_selected_section, alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end

  def set_patch
    @patch = SectionPatch.joins(:recommendation).where(recommendations: { site_id: @site.id }).find(params[:id])
  end

  def site_with_selected_section(extra_params = {})
    site_path(@site, extra_params.merge(selected_section_id: @patch.section_id))
  end
end
