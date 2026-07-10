module Sites
  class PublishedRuntime
    SnapshotSection = Data.define(:id, :uid, :kind, :name, :position, :props)

    def initialize(site)
      @site = site
    end

    def visible_section_uids
      # 当前公开运行时只开放首页 `/s/:slug`；多页公开站点需要把这里扩展成 path-aware 可见性。
      published_sections(@site.home_page).filter_map(&:uid).to_set
    end

    def visible_section_uid?(uid)
      uid.present? && visible_section_uids.include?(uid)
    end

    def published_sections(page)
      snapshot = @site.published_snapshots.order(version: :desc).first
      return [] unless snapshot

      page_payload = snapshot.payload.fetch("pages", []).find { |payload| payload["path"] == page.path }
      return [] unless page_payload

      page_payload.fetch("sections", []).map do |section_payload|
        SnapshotSection.new(
          id: section_payload["id"],
          uid: section_payload["uid"],
          kind: section_payload.fetch("kind"),
          name: section_payload.fetch("name"),
          position: section_payload.fetch("position"),
          props: section_payload.fetch("props")
        )
      end
    end
  end
end
