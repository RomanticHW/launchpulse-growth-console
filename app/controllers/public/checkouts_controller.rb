module Public
  class CheckoutsController < BaseController
    def create
      site = find_site
      product = site.products.active.find_by(key: params[:product_key].to_s)
      return render plain: "未找到该商品。", status: :not_found unless product

      section_uid = params[:section_uid].presence
      # 订单必须来自可见区块，不能只凭请求中的商品参数创建。
      return render plain: "该商品暂时无法购买。", status: :unprocessable_content unless section_uid.present? && section_uid_visible?(site, section_uid)
      section = published_section_for_uid(site, section_uid)
      # 商品必须来自实际展示它的 `product_grid` 区块。
      return render plain: "该商品暂时无法购买。", status: :unprocessable_content unless section&.kind == "product_grid"
      return render plain: "未找到该商品。", status: :not_found unless product_key_allowed_in_section?(section, params[:product_key].to_s)

      assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
      events = []
      ActiveRecord::Base.transaction do
        order = create_product_order!(site, product)
        # 订单和转化事件位于同一事务，避免出现只有订单、没有事件的记录。
        events << record_public_event!(
          site:,
          page: site.home_page,
          event_type: "checkout_click",
          metadata: { product_id: product.id, order_id: order.id },
          assignment:,
          section_uid:,
          product_key: params[:product_key],
          enqueue: false
        )
        events << record_public_event!(
          site:,
          page: site.home_page,
          event_type: "order_created",
          metadata: { product_id: product.id, order_id: order.id, total: order.total.to_s },
          assignment:,
          section_uid:,
          product_key: params[:product_key],
          enqueue: false
        )
      end
      events.each { |event| enqueue_public_event!(event) }

      redirect_to public_site_path(site.slug, ordered: 1)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "订单提交失败，请稍后重试。", status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError => error
      render plain: error.message, status: :unprocessable_content
    end

    def create_plan
      site = find_site
      section_uid = params[:section_uid].presence
      # 课程方案暂不处理支付，只创建可追踪的示例订单和转化事件。
      return render plain: "该方案暂时无法选择。", status: :unprocessable_content unless section_uid.present? && section_uid_visible?(site, section_uid)

      section = published_section_for_uid(site, section_uid)
      return render plain: "该方案暂时无法选择。", status: :unprocessable_content unless section&.kind == "pricing"
      plan = pricing_plan_for(site, section_uid, params[:plan_key].to_s)
      return render plain: "未找到该方案。", status: :not_found unless plan

      assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
      events = []
      ActiveRecord::Base.transaction do
        order = create_plan_order!(site, plan)
        events << record_public_event!(
          site:,
          page: site.home_page,
          event_type: "checkout_click",
          metadata: { plan_key: params[:plan_key], order_id: order.id },
          assignment:,
          section_uid:,
          product_key: params[:plan_key],
          enqueue: false
        )
        events << record_public_event!(
          site:,
          page: site.home_page,
          event_type: "order_created",
          metadata: { plan_key: params[:plan_key], order_id: order.id, total: order.total.to_s },
          assignment:,
          section_uid:,
          product_key: params[:plan_key],
          enqueue: false
        )
      end
      events.each { |event| enqueue_public_event!(event) }

      redirect_to public_site_path(site.slug, ordered: 1)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "订单提交失败，请稍后重试。", status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError => error
      render plain: error.message, status: :unprocessable_content
    end

    private

    def create_product_order!(site, product)
      order = site.orders.create!(
        number: "ORD-#{SecureRandom.hex(4).upcase}",
        email: params[:email].presence || "shopper@example.test",
        total: product.price,
        source: "public_checkout"
      )
      order.order_items.create!(product:, quantity: 1, unit_price: product.price)
      order
    end

    def create_plan_order!(site, plan)
      site.orders.create!(
        number: "ORD-#{SecureRandom.hex(4).upcase}",
        email: params[:email].presence || "student@example.test",
        total: price_amount(plan["price"]),
        source: "public_pricing_checkout"
      )
    end

    def pricing_plan_for(site, section_uid, plan_key)
      section = published_section_for_uid(site, section_uid)
      return nil unless section

      Array(section.props["plans"]).find { |plan| (plan["plan_key"].presence || plan["name"].to_s.parameterize) == plan_key }
    end

    def published_section_for_uid(site, section_uid)
      published_sections_for(site, site.home_page).find { |candidate| candidate.uid == section_uid }
    end

    def product_key_allowed_in_section?(section, product_key)
      Array(section.props["products"]).any? do |product|
        candidate = product["product_key"].presence || product["key"].presence || product["name"].to_s.parameterize
        candidate == product_key
      end
    end

    def price_amount(price)
      price.to_s.gsub(/[^\d.]/, "").presence || 0
    end
  end
end
