require "rails_helper"

RSpec.describe Indexer, type: :model do
  it "requires a unique Jackett ID" do
    described_class.create!(name: "First Indexer", jackett_id: "first-indexer")

    duplicate = described_class.new(name: "Duplicate Indexer", jackett_id: "first-indexer")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:jackett_id]).to include("has already been taken")
  end

  it "normalizes the Jackett ID" do
    indexer = described_class.new(name: "First Indexer", jackett_id: " first-indexer ")
    indexer.valid?

    expect(indexer.jackett_id).to eq("first-indexer")
  end

  it "normalizes a Jackett Torznab URL into a Jackett ID" do
    indexer = described_class.new(
      name: "First Indexer",
      jackett_id: "http://localhost:9117/api/v2.0/indexers/first-indexer/results/torznab/api?t=search&apikey=secret"
    )

    indexer.valid?

    expect(indexer.jackett_id).to eq("first-indexer")
  end

  it "rejects URLs that do not include a Jackett Torznab indexer path" do
    indexer = described_class.new(name: "First Indexer", jackett_id: "http://localhost:9117/")

    expect(indexer).not_to be_valid
    expect(indexer.errors[:jackett_id]).to include("must be a Jackett ID or Jackett Torznab URL")
  end
end
