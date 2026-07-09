class PublishingController < ApplicationController
  before_action :set_site

  def create
    snapshot = Sites::SnapshotService.new(@site).publish!(user: current_user, note: "手动发布")
    AuditLog.create!(account: current_account, user: current_user, site: @site, action: "published", metadata: { version: snapshot.version })
    redirect_to @site, notice: "已发布版本 #{snapshot.version}。"
  end

  def rollback
    snapshot = @site.published_snapshots.find(params[:snapshot_id])
    new_snapshot = Sites::SnapshotService.new(@site).rollback!(snapshot, user: current_user)
    redirect_to @site, notice: "已回滚到版本 #{snapshot.version}，并发布为版本 #{new_snapshot.version}。"
  rescue Sites::SnapshotService::ChecksumMismatch, Sites::SnapshotService::UnresolvedExperiments => error
    redirect_to @site, alert: error.message
  end

  def diff
    @snapshot = @site.published_snapshots.find(params[:snapshot_id])
    @diff = Sites::SnapshotService.new(@site).diff(@snapshot)
    respond_to do |format|
      format.html
      format.json { render json: @diff }
    end
  end

  private

  def set_site
    @site = current_account.sites.find(params[:site_id])
  end
end
