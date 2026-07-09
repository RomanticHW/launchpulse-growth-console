require "digest"

module Sites
  class SnapshotService
    class ChecksumMismatch < StandardError; end
    class UnresolvedExperiments < StandardError; end

    def initialize(site)
      @site = site
    end

    def publish!(user:, note: nil)
      @site.with_lock do
        version = @site.published_snapshots.maximum(:version).to_i + 1
        payload = payload_for(@site)
        # 发布是草稿进入公开运行时的唯一入口；公开页面不会直接读取正在编辑的 sections。
        @site.update!(status: "published")
        @site.published_snapshots.create!(
          version:,
          published_by: user,
          note:,
          payload:,
          checksum: checksum_for(payload),
          published_at: Time.current
        )
      end
    end

    def rollback!(snapshot, user:)
      verify_checksum!(snapshot)
      if unresolved_experiments?
        raise UnresolvedExperiments, "请先结束并应用实验胜出版本，再回滚发布。"
      end

      ActiveRecord::Base.transaction do
        retained_paths = snapshot.payload.fetch("pages", []).map { |page_payload| page_payload.fetch("path") }
        @site.pages.where.not(path: retained_paths).destroy_all

        snapshot.payload.fetch("pages", []).each do |page_payload|
          page = @site.pages.find_or_initialize_by(path: page_payload.fetch("path"))
          page.update!(title: page_payload.fetch("title"), position: page_payload.fetch("position", 0))
          retained_uids = []
          page_payload.fetch("sections", []).each do |section_payload|
            # 回滚优先按 uid 找区块，避免数据库 id 因导入或重建变化后恢复到错误位置。
            section = if section_payload["uid"].present?
              page.sections.find_or_initialize_by(uid: section_payload["uid"])
            else
              page.sections.find_or_initialize_by(kind: section_payload.fetch("kind"), position: section_payload.fetch("position"))
            end
            section.update!(
              kind: section_payload.fetch("kind"),
              name: section_payload.fetch("name"),
              position: section_payload.fetch("position"),
              props: section_payload.fetch("props")
            )
            retained_uids << section.uid
          end
          page.sections.where.not(uid: retained_uids).destroy_all
        end

        publish!(user:, note: "回滚到版本 #{snapshot.version}")
      end
    end

    def diff(snapshot)
      # 当前差异对比聚焦结构化区块属性，足够解释这次发布改了什么；视觉级对比可以作为后续编辑器能力。
      current = payload_for(@site)
      previous_sections = flattened_sections(snapshot.payload)
      current_sections = flattened_sections(current)
      previous_by_key = previous_sections.index_by { |section| section_key(section) }
      current_by_key = current_sections.index_by { |section| section_key(section) }
      added = current_by_key.keys - previous_by_key.keys
      removed = previous_by_key.keys - current_by_key.keys
      changed = changed_sections(previous_by_key, current_by_key)
      {
        "from_version" => snapshot.version,
        "current_sections" => current["pages"].sum { |page| page["sections"].size },
        "snapshot_sections" => snapshot.payload.fetch("pages", []).sum { |page| page.fetch("sections", []).size },
        "added_sections" => added.map { |key| section_summary(current_by_key.fetch(key)) },
        "removed_sections" => removed.map { |key| section_summary(previous_by_key.fetch(key)) },
        "changed_sections" => changed,
        "unchanged_count" => (previous_by_key.keys & current_by_key.keys).size - changed.size,
        "current_json" => current,
        "snapshot_json" => snapshot.payload
      }
    end

    def payload_for(site)
      {
        "site" => site.slice("id", "name", "slug", "industry", "growth_score"),
        "pages" => site.pages.order(:position).includes(:sections).map do |page|
          {
            "id" => page.id,
            "title" => page.title,
            "path" => page.path,
            "position" => page.position,
            "sections" => page.sections.order(:position).map do |section|
              section.slice("id", "uid", "kind", "name", "position", "props")
            end
          }
        end
      }
    end

    private

    def unresolved_experiments?
      @site.experiments.where(status: %w[active paused]).exists? ||
        @site.experiments.where(status: "completed", winner_applied_at: nil).exists?
    end

    def checksum_for(payload)
      # 快照校验保护的是内容，不应该依赖 Ruby 或 PostgreSQL 保留 Hash key 顺序。
      Digest::SHA256.hexdigest(canonical_json(payload))
    end

    def verify_checksum!(snapshot)
      return if snapshot.checksum.blank?

      expected_checksums = [ checksum_for(snapshot.payload), legacy_checksum_for(snapshot.payload) ].uniq
      return if expected_checksums.any? { |expected| secure_compare_digest(snapshot.checksum, expected) }

      raise ChecksumMismatch, "Snapshot checksum does not match its payload"
    end

    def canonical_json(value)
      JSON.generate(canonicalize(value))
    end

    def canonicalize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          result[key.to_s] = canonicalize(nested_value)
        end.sort.to_h
      when Array
        value.map { |nested_value| canonicalize(nested_value) }
      when Time, DateTime
        value.iso8601(6)
      when Date
        value.iso8601
      when String, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.to_s
      end
    end

    def legacy_checksum_for(payload)
      # 只兼容本地演示迭代期间旧快照的 to_json 校验；新发布统一使用 canonical checksum。
      Digest::SHA256.hexdigest(payload.to_json)
    end

    def secure_compare_digest(actual, expected)
      actual.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(actual, expected)
    end

    def flattened_sections(payload)
      payload.fetch("pages", []).flat_map { |page| page.fetch("sections", []) }
    end

    def section_key(section)
      section["uid"] || section["id"]
    end

    def section_summary(section)
      section.slice("uid", "id", "name", "kind")
    end

    def changed_sections(previous_by_key, current_by_key)
      (previous_by_key.keys & current_by_key.keys).filter_map do |key|
        old = previous_by_key.fetch(key)
        section = current_by_key.fetch(key)
        changed_keys = (old["props"].keys | section["props"].keys).select { |prop_key| old["props"][prop_key] != section["props"][prop_key] }
        next if changed_keys.empty?

        {
          "uid" => section["uid"],
          "name" => section["name"],
          "kind" => section["kind"],
          "changed_keys" => changed_keys,
          "changes" => changed_keys.each_with_object({}) do |prop_key, result|
            result[prop_key] = { "before" => old["props"][prop_key], "after" => section["props"][prop_key] }
          end
        }
      end
    end
  end
end
