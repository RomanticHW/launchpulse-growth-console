module Experiments
  class LifecycleService
    InvalidTransition = Class.new(StandardError)

    UNRESOLVED_STATUSES = %w[active paused completed].freeze

    def launch_from_recommendation!(site:, recommendation:, user:, account:)
      experiment = nil

      site.with_lock do
        recommendation.reload
        section = recommendation.section
        raise InvalidTransition, "这条建议没有关联页面区块。" unless section

        section.with_lock do
          recommendation.reload
          if recommendation.section_id != section.id
            raise InvalidTransition, "这条建议关联的页面区块已变化，请重试。"
          end

          # 实验状态流统一收在 service 里；控制器不直接改状态，避免绕过补丁和胜出版本的业务规则。
          validate_launchable!(recommendation)
          raise InvalidTransition, "这条建议已有未结束的实验。" if unresolved_recommendation_experiment?(site, recommendation)
          raise InvalidTransition, "这个区块已有未结束的实验。" if unresolved_section_experiment?(site, section)

          patch = recommendation.section_patch
          ActiveRecord::Base.transaction do
            experiment = site.experiments.create!(
              recommendation:,
              section:,
              name: "实验：#{recommendation.title}",
              status: "active",
              primary_goal: primary_goal_for(recommendation),
              started_at: Time.current
            )
            experiment.variants.create!(name: "原版本", key: "control", role: "control", props: control_props_for(section, patch), weight: 50)
            experiment.variants.create!(name: "建议版本", key: "variant", role: "variant", props: variant_props_for(section, recommendation, patch), weight: 50)
            recommendation.update!(status: "testing")
            patch&.update!(status: "testing")
            audit!(account:, user:, site:, action: "experiment_launched", experiment:, metadata: { recommendation_id: recommendation.id })
          end
        end
      end

      experiment
    end

    def pause!(experiment:, user:, account:)
      experiment.site.with_lock do
        experiment.with_lock do
          require_status!(experiment, "active", action: "pause")
          transition!(experiment:, status: "paused", user:, account:, action: "experiment_paused")
        end
      end
    end

    def resume!(experiment:, user:, account:)
      experiment.site.with_lock do
        experiment.with_lock do
          require_status!(experiment, "paused", action: "resume")
          transition!(experiment:, status: "active", user:, account:, action: "experiment_resumed", ended_at: nil)
        end
      end
    end

    def complete!(experiment:, user:, account:)
      experiment.site.with_lock do
        experiment.with_lock do
          unless %w[active paused].include?(experiment.status)
            raise InvalidTransition, "只有运行中或已暂停的实验可以完成。"
          end

          experiment.update!(status: "completed", ended_at: Time.current)
          experiment.recommendation&.update!(status: "tested") if experiment.recommendation&.status == "testing"
          experiment.recommendation&.section_patch&.update!(status: "tested") if experiment.recommendation&.section_patch&.status == "testing"
          audit!(account:, user:, site: experiment.site, action: "experiment_completed", experiment:)
        end
      end
    end

    def apply_winner!(experiment:, variant:, user:, account:)
      # 胜出版本只改变当前草稿区块，不回写补丁快照；补丁的 before/after 是实验创建时的证据。
      experiment.site.with_lock do
        experiment.with_lock do
          raise InvalidTransition, "请先完成实验，再应用胜出版本。" unless experiment.status == "completed"
          raise InvalidTransition, "胜出版本已经应用过。" if experiment.winner_applied_at.present?
          raise InvalidTransition, "该版本不属于当前实验。" if variant.experiment_id != experiment.id

          experiment.section.update!(props: variant.props)
          experiment.update!(winner_variant: variant, winner_applied_at: Time.current)
          if control_variant?(variant)
            mark_control_winner!(experiment)
            audit!(account:, user:, site: experiment.site, action: "experiment_control_won", experiment:, metadata: { variant_id: variant.id })
          else
            mark_recommended_winner!(experiment)
            audit!(account:, user:, site: experiment.site, action: "experiment_winner_applied", experiment:, metadata: { variant_id: variant.id })
          end
        end
      end
    end

    private

    def unresolved_recommendation_experiment?(site, recommendation)
      site.experiments.where(recommendation:, status: UNRESOLVED_STATUSES, winner_applied_at: nil).exists?
    end

    def unresolved_section_experiment?(site, section)
      # 当前项目不支持同一区块叠多层实验；否则公开页按 section_uid 分流时会出现归因歧义。
      site.experiments
        .where(section:)
        .where("(status IN (?) OR (status = ? AND winner_applied_at IS NULL))", %w[active paused], "completed")
        .exists?
    end

    def validate_launchable!(recommendation)
      return if recommendation.status == "open"
      if recommendation.status == "applied" && recommendation.section_patch&.status == "applied"
        # 已应用的建议只能做一次“原版本 vs 已应用版本”的复测；一旦有胜出结果，就不能重复开新实验刷结论。
        return unless recommendation.experiments.where.not(winner_applied_at: nil).exists?
      end

      raise InvalidTransition, "当前状态的建议不能启动实验。"
    end

    def require_status!(experiment, expected, action:)
      return if experiment.status == expected

      raise InvalidTransition, "当前实验状态不能执行这个操作。"
    end

    def transition!(experiment:, status:, user:, account:, action:, **attrs)
      experiment.update!(attrs.merge(status:))
      audit!(account:, user:, site: experiment.site, action:, experiment:)
    end

    def control_props_for(section, patch)
      patch&.before_props.presence || section.props
    end

    def variant_props_for(section, recommendation, patch)
      patch&.after_props.presence || section.props.deep_merge(recommendation.suggested_patch)
    end

    def primary_goal_for(recommendation)
      return "order_created" if %w[product_grid pricing].include?(recommendation.section&.kind)

      "form_submit"
    end

    def control_variant?(variant)
      variant.role == "control" || variant.key == "control"
    end

    def mark_control_winner!(experiment)
      experiment.recommendation&.update!(status: "superseded")
      experiment.recommendation&.section_patch&.update!(status: "superseded", applied: false)
    end

    def mark_recommended_winner!(experiment)
      experiment.recommendation&.update!(status: "applied", applied_at: Time.current)
      experiment.recommendation&.section_patch&.update!(
        status: "applied",
        applied: true,
        applied_at: Time.current,
        reverted_at: nil
      )
    end

    def audit!(account:, user:, site:, action:, experiment:, metadata: {})
      AuditLog.create!(account:, user:, site:, action:, metadata: metadata.merge(experiment_id: experiment.id))
    end
  end
end
