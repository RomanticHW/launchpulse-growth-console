class AiAuditsController < ApplicationController
  before_action :set_site
  before_action :require_editor!

  def create
    audit = Ai::GrowthAuditService.new(@site).call
    AuditLog.create!(account: current_account, user: current_user, site: @site, action: "created_audit", metadata: { audit_id: audit.id })
    redirect_to @site, notice: "已生成 #{audit.ai_findings.count} 条增长建议。"
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end
end
