require "rails_helper"

RSpec.describe Events::IngestionService do
  it "takes the idempotency advisory lock through the Active Record adapter" do
    site = create(:site)
    service = described_class.allocate
    connection = ActiveRecord::Base.connection
    allow(connection).to receive(:execute).and_call_original

    service.send(:with_idempotency_lock, site, "event-key") { }

    expect(connection).to have_received(:execute).with(/\ASELECT pg_advisory_xact_lock\(\d+\)\z/)
  end
end
