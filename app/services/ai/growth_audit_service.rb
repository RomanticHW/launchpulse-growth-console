module Ai
  class GrowthAuditService
    def initialize(site)
      @site = site
    end

    def call
      ActiveRecord::Base.transaction do
        # 当前建议由固定规则生成，确保本地运行和测试不依赖外部服务。
        # 后续接入外部服务时仍保留规则兜底，避免页面分析因第三方故障完全不可用。
        audit = @site.ai_audits.create!(
          status: "completed",
          score: calculated_score,
          summary: "页面分析完成，已生成可预览的优化建议。",
          input_snapshot: Sites::SnapshotService.new(@site).payload_for(@site)
        )

        recommendations_for(@site).each do |item|
          # 相同建议只保留一条待处理记录，避免重复分析产生重复任务。
          next if @site.recommendations.where(section: item[:section], title: item[:title], status: %w[open testing tested applied dismissed superseded]).exists?

          finding = audit.ai_findings.create!(
            section: item[:section],
            severity: item[:severity],
            problem: item[:problem],
            evidence: item[:evidence]
          )

          recommendation = @site.recommendations.create!(
            ai_finding: finding,
            section: item[:section],
            title: item[:title],
            problem: item[:problem],
            suggested_patch: item[:suggested_patch],
            expected_impact: item[:expected_impact],
            confidence: item[:confidence]
          )

          # 修改前后的内容同时写入补丁，供预览、实验和撤回使用。
          recommendation.create_section_patch!(
            section: item[:section],
            props_diff: item[:suggested_patch],
            before_props: item[:section]&.props || {},
            after_props: (item[:section]&.props || {}).deep_merge(item[:suggested_patch]),
            status: "pending"
          )
        end

        @site.update!(growth_score: audit.score)
        audit
      end
    end

    private

    def calculated_score
      base = 68
      base += 8 if @site.sections.exists?(kind: "testimonial")
      base += 6 if @site.sections.exists?(kind: "faq")
      base += 5 if @site.sections.exists?(kind: "pricing") || @site.sections.exists?(kind: "product_grid")
      [ base, 92 ].min
    end

    def recommendations_for(site)
      site.sections.order(:position).filter_map do |section|
        case section.kind
        when "hero" then build_hero_recommendation(section)
        when "feature_grid" then build_feature_grid_recommendation(section)
        when "contact_form" then build_contact_form_recommendation(section)
        when "pricing" then build_pricing_recommendation(section)
        when "product_grid" then build_product_grid_recommendation(section)
        when "faq" then build_faq_recommendation(section)
        when "testimonial" then build_testimonial_recommendation(section)
        end
      end
    end

    def build_hero_recommendation(section)
      recommendation_for(
        section:,
        title: "明确首屏按钮的操作结果",
        severity: "high",
        problem: "当前按钮文案较笼统，访客点击前难以判断下一步内容。",
        evidence: "按钮写清楚操作结果，可以减少访客对后续步骤的疑问。",
        suggested_patch: {
          "cta" => "查看详细方案",
          "subheadline" => "了解服务内容、适用场景和后续安排，再决定是否继续。"
        },
        expected_impact: "重点观察首屏按钮点击率",
        confidence: 0.86
      )
    end

    def build_feature_grid_recommendation(section)
      recommendation_for(
        section:,
        title: "补充具体的选择理由",
        severity: "medium",
        problem: "卖点描述较宽泛，缺少能帮助访客判断的具体信息。",
        evidence: "服务内容、办理流程和重要限制越清楚，访客越容易做出选择。",
        suggested_patch: {
          "headline" => "选择我们的三个理由",
          "items" => [
            { "title" => "服务内容清楚", "body" => "页面直接说明提供什么，以及适合哪些使用场景。" },
            { "title" => "办理流程明确", "body" => "提交信息后会收到什么、何时回复，都提前说明。" },
            { "title" => "重要信息透明", "body" => "价格、范围和限制集中展示，方便访客比较。" }
          ]
        },
        expected_impact: "重点观察表单提交率和下单率",
        confidence: 0.74
      )
    end

    def build_contact_form_recommendation(section)
      recommendation_for(
        section:,
        title: "说明提交后的联系安排",
        severity: "medium",
        problem: "表单没有说明提交后的回复时间和联系方式。",
        evidence: "提前说明后续安排，可以减少填写过程中的不确定感。",
        suggested_patch: {
          "submit_label" => "提交需求",
          "helper" => "提交后，工作人员将在 1 个工作日内与你联系。"
        },
        expected_impact: "重点观察表单完成率",
        confidence: 0.71
      )
    end

    def build_pricing_recommendation(section)
      recommendation_for(
        section:,
        title: "突出不同方案的适用人群",
        severity: "medium",
        problem: "各档方案只列出价格和内容，适用人群不够明确。",
        evidence: "说明每档方案适合谁，可以帮助访客缩短比较时间。",
        suggested_patch: {
          "headline" => "按学习方式选择课程方案",
          "plans" => Array(section.props["plans"]).presence || [
            { "name" => "自学版", "plan_key" => "starter", "price" => "¥999", "description" => "录播课程、配套模板和学习清单。" },
            { "name" => "辅导版", "plan_key" => "guided", "price" => "¥2,699", "description" => "包含作业点评和每周直播答疑。" }
          ]
        },
        expected_impact: "重点观察方案选择率和订单创建率",
        confidence: 0.69
      )
    end

    def build_product_grid_recommendation(section)
      recommendation_for(
        section:,
        title: "帮助顾客更快找到合适商品",
        severity: "medium",
        problem: "产品列表只展示名称和价格，没有说明推荐组合或适用场景。",
        evidence: "按使用需求组织商品，可以减少顾客来回比较的时间。",
        suggested_patch: {
          "headline" => "按日常需求选择",
          "products" => Array(section.props["products"]).presence || [
            { "name" => "基础护理套装", "product_key" => "starter-routine", "price" => "¥599" }
          ]
        },
        expected_impact: "重点观察商品点击率和订单创建率",
        confidence: 0.72
      )
    end

    def build_faq_recommendation(section)
      recommendation_for(
        section:,
        title: "补充下单前常见问题",
        severity: "low",
        problem: "当前问答没有覆盖提交或购买后的具体安排。",
        evidence: "把回复时间、交付方式等常见问题提前说明，可以减少重复咨询。",
        suggested_patch: {
          "headline" => "购买前常见问题",
          "items" => Array(section.props["items"]).presence || [
            { "question" => "提交后多久会收到回复？", "answer" => "工作人员会在 1 个工作日内通过邮件与你联系。" }
          ]
        },
        expected_impact: "重点观察咨询提交率和购买转化率",
        confidence: 0.64
      )
    end

    def build_testimonial_recommendation(section)
      recommendation_for(
        section:,
        title: "补充更具体的使用反馈",
        severity: "low",
        problem: "当前反馈较笼统，没有说明具体的使用感受或服务过程。",
        evidence: "包含场景和细节的反馈更便于访客判断是否符合自己的需要。",
        suggested_patch: {
          "quote" => "页面说明很清楚，提交后很快就知道下一步怎么安排。",
          "author" => section.props["author"].presence || "用户反馈示例"
        },
        expected_impact: "重点观察表单提交率和购买转化率",
        confidence: 0.62
      )
    end

    def recommendation_for(section:, title:, severity:, problem:, evidence:, suggested_patch:, expected_impact:, confidence:)
      {
        section:,
        title:,
        severity:,
        problem:,
        evidence:,
        suggested_patch:,
        expected_impact:,
        confidence:
      }
    end
  end
end
