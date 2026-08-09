require "rails_helper"

RSpec.describe Jackett::InventoryRefresh do
  let(:discovery) { class_double(Jackett::IndexerDiscovery) }
  let(:reconciler) { class_double(Jackett::InventoryReconciler) }
  let(:seen_at) { Time.zone.local(2026, 8, 9, 15, 30) }

  it "reconciles a successful Jackett inventory" do
    records = [
      Jackett::IndexerDiscovery::IndexerRecord.new(
        name: "EZTV",
        jackett_id: "eztv",
        configured: true
      )
    ]
    result = discovery_result(success: true, indexers: records)
    allow(discovery).to receive(:call).and_return(result)
    allow(reconciler).to receive(:call)

    returned = described_class.call(
      base_url: "http://jackett.example.test",
      api_key: "jackett-key",
      seen_at:,
      discovery:,
      reconciler:
    )

    expect(returned).to equal(result)
    expect(discovery).to have_received(:call).with(
      base_url: "http://jackett.example.test",
      api_key: "jackett-key"
    )
    expect(reconciler).to have_received(:call).with(records:, seen_at:)
  end

  it "does not reconcile a failed or incomplete inventory response" do
    result = discovery_result(success: false, indexers: [])
    allow(discovery).to receive(:call).and_return(result)
    allow(reconciler).to receive(:call)

    returned = described_class.call(
      base_url: "http://jackett.example.test",
      api_key: "jackett-key",
      seen_at:,
      discovery:,
      reconciler:
    )

    expect(returned).to equal(result)
    expect(reconciler).not_to have_received(:call)
  end

  private

    def discovery_result(success:, indexers:)
      Jackett::IndexerDiscovery::Result.new(
        success?: success,
        indexers:,
        message: success ? "Found indexers." : "Could not read inventory.",
        error: ("Could not read inventory." unless success),
        http_status: success ? 200 : 502
      )
    end
end
