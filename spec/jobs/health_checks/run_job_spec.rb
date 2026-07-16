require "rails_helper"

RSpec.describe HealthChecks::RunJob, type: :job do
  it "invokes the shared runner" do
    allow(HealthChecks::Runner).to receive(:call)

    described_class.perform_now

    expect(HealthChecks::Runner).to have_received(:call)
  end

  it "declares one full-cycle concurrency slot" do
    expect(described_class).to have_attributes(
      concurrency_group: "health_checks",
      concurrency_limit: 1,
      concurrency_duration: described_class::CONCURRENCY_DURATION
    )
    expect(described_class.new.concurrency_key).to eq("health_checks/full-cycle")
  end

  it "uses the same job behavior when manually enqueued" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end
end
