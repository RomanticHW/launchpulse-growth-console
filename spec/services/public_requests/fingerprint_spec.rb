require "rails_helper"

RSpec.describe "Public request fingerprints" do
  let(:fingerprint_class) { PublicRequests::Fingerprint }

  it "is stable across nested hash key ordering" do
    first = fingerprint_class.call(
      operation: "form_submission",
      attributes: { form_id: 1, payload: { email: "lead@example.test", profile: { b: 2, a: 1 } } }
    )
    second = fingerprint_class.call(
      operation: "form_submission",
      attributes: { payload: { profile: { a: 1, b: 2 }, email: "lead@example.test" }, form_id: 1 }
    )

    expect(first).to eq(second)
    expect(first).to match(/\A[0-9a-f]{64}\z/)
    expect(first).not_to include("lead@example.test")
  end

  it "changes when the operation, target, or business payload changes" do
    product = fingerprint_class.call(
      operation: "product_checkout",
      attributes: { target_key: "calm-cream", section_uid: "products", email: "buyer@example.test" }
    )
    other_product = fingerprint_class.call(
      operation: "product_checkout",
      attributes: { target_key: "night-cream", section_uid: "products", email: "buyer@example.test" }
    )
    plan = fingerprint_class.call(
      operation: "plan_checkout",
      attributes: { target_key: "calm-cream", section_uid: "products", email: "buyer@example.test" }
    )
    other_email = fingerprint_class.call(
      operation: "product_checkout",
      attributes: { target_key: "calm-cream", section_uid: "products", email: "other@example.test" }
    )

    expect([ other_product, plan, other_email ]).not_to include(product)
  end

  it "normalizes ActionController parameters without relying on insertion order" do
    params = ActionController::Parameters.new(email: "lead@example.test", answers: { b: "2", a: "1" })
    hash = { "answers" => { "a" => "1", "b" => "2" }, "email" => "lead@example.test" }

    expect(fingerprint_class.call(operation: "form_submission", attributes: params))
      .to eq(fingerprint_class.call(operation: "form_submission", attributes: hash))
  end
end
