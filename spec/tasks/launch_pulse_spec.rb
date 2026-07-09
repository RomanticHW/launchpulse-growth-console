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
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output

    expect do
      task.invoke
    end.to have_enqueued_job(AggregateEventJob).exactly(unaggregated.size).times

    expect(output.string).to include("Enqueued 2 unaggregated events")
  ensure
    $stdout = original_stdout
  end
end
