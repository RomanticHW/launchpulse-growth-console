class DashboardRefreshJob < ApplicationJob
  queue_as :default

  def perform(site_id, kind)
    site = Site.find_by(id: site_id)
    return unless site

    broadcaster = Analytics::DashboardBroadcaster.new(site)
    case kind.to_s
    when "summary"
      broadcaster.broadcast_summary(force: true)
    when "experiments"
      broadcaster.broadcast_experiments(force: true)
    end
  ensure
    if site
      Rails.cache.delete("dashboard_broadcast:#{kind}:scheduled:site:#{site.id}")
    end
  end
end
