require "rails_helper"
require "rake"

RSpec.describe "launch_pulse tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:task) { Rake::Task["launch_pulse:enqueue_unaggregated_events"] }

  before do
    task.reenable
  end

  it "enqueues aggregation jobs for unaggregated events only" do
    site = create(:site)
    unaggregated = 2.times.map do |index|
      site.events.create!(
        event_type: "page_view",
        visitor_id: "visitor-unaggregated-#{index}",
        occurred_at: Time.current
      )
    end
    site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-aggregated",
      aggregated_at: Time.current,
      occurred_at: Time.current
    )
    site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-active-lease",
      aggregation_enqueued_at: 5.minutes.ago,
      occurred_at: Time.current
    )
    expired = site.events.create!(
      event_type: "page_view",
      visitor_id: "visitor-expired-lease",
      aggregation_enqueued_at: 11.minutes.ago,
      occurred_at: Time.current
    )
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output

    expect do
      task.invoke
    end.to have_enqueued_job(AggregateEventJob).exactly(unaggregated.size + 1).times

    expect(output.string).to include("Claimed 3; enqueued 3 unaggregated events")
    expect(expired.reload.aggregation_enqueued_at).to be_within(1.second).of(Time.current)
  ensure
    $stdout = original_stdout
  end
end
