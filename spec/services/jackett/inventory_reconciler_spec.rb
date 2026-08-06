require "rails_helper"

RSpec.describe Jackett::InventoryReconciler do
  it "records renames, disabled indexers, and missing imported indexers" do
    renamed = Indexer.create!(name: "Old Name", jackett_id: "renamed")
    disabled = Indexer.create!(name: "Disabled", jackett_id: "disabled")
    missing = Indexer.create!(name: "Missing", jackett_id: "missing")
    seen_at = Time.zone.local(2026, 8, 6, 12)
    records = [
      Jackett::IndexerDiscovery::IndexerRecord.new(name: "New Name", jackett_id: "renamed", configured: true),
      Jackett::IndexerDiscovery::IndexerRecord.new(name: "Disabled", jackett_id: "disabled", configured: false)
    ]

    result = described_class.call(records:, seen_at:)

    expect(result.changed_count).to eq(2)
    expect(result.missing_count).to eq(1)
    expect(renamed.reload.jackett_state).to eq("renamed")
    expect(renamed.jackett_name).to eq("New Name")
    expect(disabled.reload.jackett_state).to eq("disabled")
    expect(missing.reload.jackett_state).to eq("missing")
    expect(missing.jackett_missing_since).to eq(seen_at)
  end

  it "marks an unchanged imported indexer as unchanged" do
    indexer = Indexer.create!(name: "Same", jackett_id: "same")
    record = Jackett::IndexerDiscovery::IndexerRecord.new(name: "Same", jackett_id: "same", configured: true)

    described_class.call(records: [ record ])

    expect(indexer.reload.jackett_state).to eq("unchanged")
    expect(indexer.jackett_source_digest).to eq(record.source_digest)
    expect(indexer.jackett_last_seen_at).to be_present
  end

  it "detects source configuration changes without a rename" do
    indexer = Indexer.create!(
      name: "Same",
      jackett_id: "same",
      jackett_name: "Same",
      jackett_configured: true,
      jackett_source_digest: "old-fingerprint"
    )
    record = Jackett::IndexerDiscovery::IndexerRecord.new(
      name: "Same",
      jackett_id: "same",
      configured: true,
      fingerprint: "new-fingerprint"
    )

    described_class.call(records: [ record ])

    expect(indexer.reload.jackett_state).to eq("changed")
    expect(indexer.jackett_source_digest).to eq("new-fingerprint")
  end

  it "preserves when an indexer first went missing across later discoveries" do
    first_missing_at = Time.zone.local(2026, 8, 5, 12)
    indexer = Indexer.create!(
      name: "Missing",
      jackett_id: "missing",
      jackett_state: "missing",
      jackett_missing_since: first_missing_at
    )

    described_class.call(records: [], seen_at: first_missing_at + 1.day)

    expect(indexer.reload.jackett_missing_since).to eq(first_missing_at)
  end
end
