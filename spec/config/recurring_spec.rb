require "rails_helper"
require "yaml"

RSpec.describe "recurring job configuration" do
  it "runs unaggregated event recovery every five minutes in production" do
    production = YAML.safe_load(Rails.root.join("config/recurring.yml").read).fetch("production")

    expect(production.fetch("requeue_unaggregated_events")).to eq(
      "class" => "RequeueUnaggregatedEventsJob",
      "schedule" => "every 5 minutes"
    )
    expect(production).to have_key("clear_solid_queue_finished_jobs")
  end
end
