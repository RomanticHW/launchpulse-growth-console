require "rails_helper"

RSpec.describe "Public request idempotency" do
  let(:request_token) { SecureRandom.uuid }

  it "validates form submission request tokens within each form" do
    form = create(:site).forms.create!(name: "Lead form")
    form.form_submissions.create!(payload: { "email" => "first@example.test" }, request_token:)

    duplicate = form.form_submissions.build(payload: { "email" => "second@example.test" }, request_token:)
    other_form_submission = create(:site).forms.create!(name: "Other form").form_submissions.build(
      payload: { "email" => "other@example.test" },
      request_token:
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:request_token]).to be_present
    expect(other_form_submission).to be_valid
  end

  it "validates order request tokens within each site" do
    site = create(:site)
    site.orders.create!(number: "ORD-1", email: "first@example.test", total: 10, request_token:)

    duplicate = site.orders.build(number: "ORD-2", email: "second@example.test", total: 20, request_token:)
    other_site_order = create(:site).orders.build(
      number: "ORD-1",
      email: "other@example.test",
      total: 30,
      request_token:
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:request_token]).to be_present
    expect(other_site_order).to be_valid
  end

  it "allows nil request tokens for legacy callers" do
    form = create(:site).forms.create!(name: "Lead form")
    site = create(:site)

    expect(form.form_submissions.create!(payload: { "email" => "first@example.test" }, request_token: nil)).to be_persisted
    expect(form.form_submissions.create!(payload: { "email" => "second@example.test" }, request_token: nil)).to be_persisted
    expect(site.orders.create!(number: "ORD-1", email: "first@example.test", total: 10, request_token: nil)).to be_persisted
    expect(site.orders.create!(number: "ORD-2", email: "second@example.test", total: 20, request_token: nil)).to be_persisted
  end

  it "rejects malformed and oversized request tokens" do
    form = create(:site).forms.create!(name: "Lead form")
    site = create(:site)

    malformed_submission = form.form_submissions.build(payload: { "email" => "lead@example.test" }, request_token: "not-a-uuid")
    oversized_order = site.orders.build(number: "ORD-1", email: "buyer@example.test", total: 10, request_token: "x" * 101)

    expect(malformed_submission).not_to be_valid
    expect(malformed_submission.errors[:request_token]).to be_present
    expect(oversized_order).not_to be_valid
    expect(oversized_order.errors[:request_token]).to be_present
  end

  it "enforces form request token uniqueness in PostgreSQL" do
    form = create(:site).forms.create!(name: "Lead form")

    expect do
      FormSubmission.transaction(requires_new: true) do
        form.form_submissions.create!(payload: { "email" => "first@example.test" }, request_token:)
        duplicate = form.form_submissions.build(payload: { "email" => "second@example.test" }, request_token:)
        duplicate.save!(validate: false)
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces order request token uniqueness in PostgreSQL" do
    site = create(:site)

    expect do
      Order.transaction(requires_new: true) do
        site.orders.create!(number: "ORD-1", email: "first@example.test", total: 10, request_token:)
        duplicate = site.orders.build(number: "ORD-2", email: "second@example.test", total: 20, request_token:)
        duplicate.save!(validate: false)
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "uses partial unique indexes so nil tokens remain compatible" do
    form_index = ActiveRecord::Base.connection.indexes(:form_submissions).find do |index|
      index.name == "idx_form_submissions_unique_request_token"
    end
    order_index = ActiveRecord::Base.connection.indexes(:orders).find do |index|
      index.name == "idx_orders_unique_request_token"
    end

    expect(form_index).to have_attributes(
      columns: %w[form_id request_token],
      unique: true,
      where: "(request_token IS NOT NULL)"
    )
    expect(order_index).to have_attributes(
      columns: %w[site_id request_token],
      unique: true,
      where: "(request_token IS NOT NULL)"
    )
  end
end
