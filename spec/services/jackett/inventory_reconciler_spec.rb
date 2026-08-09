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

  it "keeps a rename pending across automatic inventory refreshes until it is accepted" do
    indexer = Indexer.create!(
      name: "Old Name",
      jackett_id: "renamed",
      jackett_name: "Old Name",
      jackett_source_digest: "accepted-fingerprint",
      jackett_state: "unchanged"
    )
    record = Jackett::IndexerDiscovery::IndexerRecord.new(
      name: "New Name",
      jackett_id: "renamed",
      configured: true,
      fingerprint: "renamed-fingerprint"
    )

    2.times { described_class.call(records: [ record ]) }

    expect(indexer.reload).to have_attributes(
      jackett_name: "New Name",
      jackett_state: "renamed",
      jackett_source_digest: "accepted-fingerprint"
    )
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
    expect(indexer.jackett_source_digest).to eq("old-fingerprint")

    described_class.call(records: [ record ])

    expect(indexer.reload.jackett_state).to eq("changed")
    expect(indexer.jackett_source_digest).to eq("old-fingerprint")
  end

  it "clears an unaccepted source change when Jackett returns to the accepted configuration" do
    indexer = Indexer.create!(
      name: "Same",
      jackett_id: "same",
      jackett_name: "Same",
      jackett_configured: true,
      jackett_source_digest: "accepted-fingerprint",
      jackett_state: "changed"
    )
    record = Jackett::IndexerDiscovery::IndexerRecord.new(
      name: "Same",
      jackett_id: "same",
      configured: true,
      fingerprint: "accepted-fingerprint"
    )

    described_class.call(records: [ record ])

    expect(indexer.reload.jackett_state).to eq("unchanged")
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

  it "broadcasts bulk missing-state changes that bypass model callbacks" do
    Indexer.create!(name: "Missing", jackett_id: "missing")
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)

    described_class.call(records: [])

    %w[dashboard readiness indexers assignment_matrix].each do |stream|
      expect(Turbo::StreamsChannel).to have_received(:broadcast_refresh_later_to).with(stream)
    end
  end
end
