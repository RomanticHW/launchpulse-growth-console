module Public
  class CheckoutsController < BaseController
    CheckoutUnavailable = Class.new(StandardError)
    CheckoutTargetNotFound = Class.new(StandardError)

    def create
      site = find_site
      section_uid = params[:section_uid].presence
      request_token = validated_request_token
      product_key = params[:product_key].to_s
      email = checkout_email("shopper@example.test")
      request_fingerprint = order_request_fingerprint(
        operation: "product_checkout",
        target_key: product_key,
        section_uid:,
        email:,
        request_token:
      )
      order = resolve_order(site:, request_token:, request_fingerprint:) do
        create_product_checkout!(
          site:,
          product_key:,
          section_uid:,
          email:,
          request_token:,
          request_fingerprint:
        )
      end
      enqueue_pending_order_events!(site, order)

      redirect_after_checkout(site)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "订单创建失败，请稍后重试", status: :unprocessable_content
    rescue RequestFingerprintMismatch => error
      render plain: error.message, status: :conflict
    rescue CheckoutTargetNotFound => error
      render plain: error.message, status: :not_found
    rescue CheckoutUnavailable => error
      render plain: error.message, status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError, InvalidRequestToken => error
      render plain: error.message, status: :unprocessable_content
    end

    def create_plan
      site = find_site
      section_uid = params[:section_uid].presence
      request_token = validated_request_token
      plan_key = params[:plan_key].to_s
      email = checkout_email("student@example.test")
      request_fingerprint = order_request_fingerprint(
        operation: "plan_checkout",
        target_key: plan_key,
        section_uid:,
        email:,
        request_token:
      )
      order = resolve_order(site:, request_token:, request_fingerprint:) do
        create_plan_checkout!(
          site:,
          plan_key:,
          section_uid:,
          email:,
          request_token:,
          request_fingerprint:
        )
      end
      enqueue_pending_order_events!(site, order)

      redirect_after_checkout(site)
    rescue ActiveRecord::RecordInvalid => error
      render plain: "订单创建失败，请稍后重试", status: :unprocessable_content
    rescue RequestFingerprintMismatch => error
      render plain: error.message, status: :conflict
    rescue CheckoutTargetNotFound => error
      render plain: error.message, status: :not_found
    rescue CheckoutUnavailable => error
      render plain: error.message, status: :unprocessable_content
    rescue Events::MetadataSanitizer::InvalidMetadata, HiddenSectionError, InvalidRequestToken => error
      render plain: error.message, status: :unprocessable_content
    end

    private

    def resolve_order(site:, request_token:, request_fingerprint:, &creation)
      operation = proc do
        existing = find_order_by_request_token(site, request_token)
        existing ? ensure_matching_request_fingerprint!(existing, request_fingerprint) : creation.call
      end

      if request_token
        PublicRequests::IdempotencyLock.with_lock(
          scope: "site:#{site.id}",
          request_token:,
          &operation
        )
      else
        ActiveRecord::Base.transaction(&operation)
      end
    rescue ActiveRecord::RecordNotUnique => error
      raise unless request_token_constraint_violation?(error, Order::REQUEST_TOKEN_INDEX_NAME)

      recover_order!(site, request_token, request_fingerprint, error)
    rescue ActiveRecord::RecordInvalid => error
      raise unless order_request_token_taken?(error)

      recover_order!(site, request_token, request_fingerprint, error)
    end

    def create_product_checkout!(site:, product_key:, section_uid:, email:, request_token:, request_fingerprint:)
      product = site.products.active.find_by(key: product_key)
      raise CheckoutTargetNotFound, "商品不存在" unless product
      raise CheckoutUnavailable, "该商品暂不可购买" unless section_uid.present? && section_uid_visible?(site, section_uid)

      section = published_section_for_uid(site, section_uid)
      # 商品结账必须归到真正展示该商品的 product_grid，不能让 hero/faq 等区块伪造订单归因。
      raise CheckoutUnavailable, "该商品暂不可购买" unless section&.kind == "product_grid"
      raise CheckoutTargetNotFound, "商品不存在" unless product_key_allowed_in_section?(section, product_key)

      order = create_product_order!(site, product, email:, request_token:, request_fingerprint:)
      assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
      record_order_events!(site:, order:, assignment:, section_uid:, product:, product_key:)
      order
    end

    def create_plan_checkout!(site:, plan_key:, section_uid:, email:, request_token:, request_fingerprint:)
      # 定价卡片不接真实支付，这里创建可追踪的演示订单，用来打通课程/服务型站点的转化闭环。
      raise CheckoutUnavailable, "该方案暂不可选择" unless section_uid.present? && section_uid_visible?(site, section_uid)

      section = published_section_for_uid(site, section_uid)
      raise CheckoutUnavailable, "该方案暂不可选择" unless section&.kind == "pricing"

      plan = pricing_plan_for(site, section_uid, plan_key)
      raise CheckoutTargetNotFound, "方案不存在" unless plan

      order = create_plan_order!(site, plan, email:, request_token:, request_fingerprint:)
      assignment = assignment_for_section_uid(site, section_uid, require_visible: true)
      record_order_events!(site:, order:, assignment:, section_uid:, product_key: plan_key)
      order
    end

    def create_product_order!(site, product, email:, request_token:, request_fingerprint:)
      order = site.orders.create!(
        number: "ORD-#{SecureRandom.hex(4).upcase}",
        email:,
        total: product.price,
        source: "public_checkout",
        request_token:,
        request_fingerprint:
      )
      order.order_items.create!(product:, quantity: 1, unit_price: product.price)
      order
    end

    def create_plan_order!(site, plan, email:, request_token:, request_fingerprint:)
      site.orders.create!(
        number: "ORD-#{SecureRandom.hex(4).upcase}",
        email:,
        total: price_amount(plan["price"]),
        source: "public_pricing_checkout",
        request_token:,
        request_fingerprint:
      )
    end

    def record_order_events!(site:, order:, assignment:, section_uid:, product_key:, product: nil)
      target_metadata = product ? { product_id: product.id } : { plan_key: product_key }
      record_public_event!(
        site:,
        page: site.home_page,
        event_type: "checkout_click",
        metadata: target_metadata.merge(order_id: order.id),
        assignment:,
        section_uid:,
        product_key:,
        enqueue: false
      )
      record_public_event!(
        site:,
        page: site.home_page,
        event_type: "order_created",
        metadata: target_metadata.merge(order_id: order.id, total: order.total.to_s),
        assignment:,
        section_uid:,
        product_key:,
        enqueue: false
      )
    end

    def recover_order!(site, request_token, request_fingerprint, original_error)
      existing = find_order_by_request_token(site, request_token)
      raise original_error unless existing

      ensure_matching_request_fingerprint!(existing, request_fingerprint)
    end

    def order_request_token_taken?(error)
      error.record.is_a?(Order) && error.record.errors.of_kind?(:request_token, :taken)
    end

    def order_request_fingerprint(operation:, target_key:, section_uid:, email:, request_token:)
      return nil unless request_token

      PublicRequests::Fingerprint.call(
        operation:,
        attributes: { target_key:, section_uid:, email: }
      )
    end

    def checkout_email(default_email)
      params[:email].presence || default_email
    end

    def enqueue_pending_order_events!(site, order)
      site.events
        .where(event_type: %w[checkout_click order_created], aggregated_at: nil)
        .where("metadata @> ?", { order_id: order.id }.to_json)
        .find_each { |event| enqueue_public_event!(event) }
    end

    def find_order_by_request_token(site, request_token)
      return nil unless request_token

      Order.find_by(site_id: site.id, request_token:)
    end

    def redirect_after_checkout(site)
      redirect_to public_site_path(site.slug, ordered: 1)
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
