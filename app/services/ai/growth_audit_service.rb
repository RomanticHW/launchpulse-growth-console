module Ai
  class GrowthAuditService
    def initialize(site)
      @site = site
    end

    def call
      ActiveRecord::Base.transaction do
        # 这里先保留确定性审计：本地运行不依赖外部密钥，测试也能稳定断言建议内容。
        # 真实产品接入模型后，仍然应该保留这种兜底路径，避免增长闭环被第三方接口拖垮。
        audit = @site.ai_audits.create!(
          status: "completed",
          score: calculated_score,
          summary: "转化诊断已完成，并生成稳定的演示建议。",
          input_snapshot: Sites::SnapshotService.new(@site).payload_for(@site)
        )

        recommendations_for(@site).each do |item|
          # 审计输出是确定性的，重复运行不应该把同一条建议刷成多条待处理记录。
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

          # 建议必须落成补丁，而不是只停留在文案；后面的预览、实验和回滚都依赖这份 before/after 证据。
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
        title: "让首屏行动更明确",
        severity: "high",
        problem: "首屏按钮表达偏泛，访客不容易判断下一步能得到什么。",
        evidence: "页面浏览量不低，但点按钮的人不多，首屏没把访客的兴趣接住。",
        suggested_patch: {
          "cta" => "领取方案",
          "subheadline" => "用更明确的承诺和单一行动，把更多访客带到下一步。"
        },
        expected_impact: "按钮点击率预计提升 8-14%",
        confidence: 0.86
      )
    end

    def build_feature_grid_recommendation(section)
      recommendation_for(
        section:,
        title: "把可信理由前置",
        severity: "medium",
        problem: "访客先看到的是卖点，但还没看到能让人放心的理由。",
        evidence: "小商家的页面通常得先让人放心，访客才会填表单或下单。",
        suggested_patch: {
          "headline" => "为什么顾客会选择我们",
          "items" => [
            { "title" => "本地口碑", "body" => "填表单或下单之前，先给一个具体、接地气的理由。" },
            { "title" => "下一步明确", "body" => "按钮写清楚要做什么，能少一点犹豫。" },
            { "title" => "承诺具体", "body" => "卖点保持清楚，访客更容易比较。" }
          ]
        },
        expected_impact: "转化率预计提升 4-9%",
        confidence: 0.74
      )
    end

    def build_contact_form_recommendation(section)
      recommendation_for(
        section:,
        title: "降低表单顾虑",
        severity: "medium",
        problem: "提交按钮没有说明后续会如何跟进。",
        evidence: "清楚的回复时间能减少访客填写表单前的犹豫。",
        suggested_patch: {
          "submit_label" => "提交需求",
          "helper" => "我们会在 1 个工作日内回复。"
        },
        expected_impact: "表单完成率预计提升 3-7%",
        confidence: 0.71
      )
    end

    def build_pricing_recommendation(section)
      recommendation_for(
        section:,
        title: "让价格方案更容易比较",
        severity: "medium",
        problem: "三档价格摆在一起，但看不出该选哪个。",
        evidence: "对比越简单直接，越容易让人快速定下来。",
        suggested_patch: {
          "headline" => "选一个适合你现在阶段的方案",
          "plans" => Array(section.props["plans"]).presence || [
            { "name" => "入门版", "plan_key" => "starter", "price" => "$149", "description" => "模板和发布清单。" },
            { "name" => "陪跑版", "plan_key" => "guided", "price" => "$399", "description" => "点评和每周发布支持。" }
          ]
        },
        expected_impact: "下单意愿预计提升 3-6%",
        confidence: 0.69
      )
    end

    def build_product_grid_recommendation(section)
      recommendation_for(
        section:,
        title: "强化产品选择路径",
        severity: "medium",
        problem: "产品列表没有把推荐套组讲清楚。",
        evidence: "选择越简单，顾客越容易直接下单。",
        suggested_patch: {
          "headline" => "顾客回购最多的套组",
          "products" => Array(section.props["products"]).presence || [
            { "name" => "入门护理套组", "product_key" => "starter-routine", "price" => "$84" }
          ]
        },
        expected_impact: "产品点击预计提升 4-8%",
        confidence: 0.72
      )
    end

    def build_faq_recommendation(section)
      recommendation_for(
        section:,
        title: "提前回答购买顾虑",
        severity: "low",
        problem: "问答内容还可以更直接地处理购买前犹豫。",
        evidence: "具体回答能在表单或购买前减少不确定感。",
        suggested_patch: {
          "headline" => "决定前常见的问题",
          "items" => Array(section.props["items"]).presence || [
            { "question" => "提交后会发生什么？", "answer" => "你会通过邮箱收到明确的下一步和时间安排。" }
          ]
        },
        expected_impact: "后续转化预计提升 2-5%",
        confidence: 0.64
      )
    end

    def build_testimonial_recommendation(section)
      recommendation_for(
        section:,
        title: "让用户评价更具体",
        severity: "low",
        problem: "当前评价可以把结果说得更具体。",
        evidence: "评价写得越具体，访客越容易联想到自己的情况。",
        suggested_patch: {
          "quote" => "下一步很清楚，我也知道为什么它适合我当下的需求。",
          "author" => section.props["author"].presence || "真实用户"
        },
        expected_impact: "信任感预计提升 2-4%",
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
