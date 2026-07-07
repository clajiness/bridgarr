require "rails_helper"

RSpec.describe Arr::TorznabCategoryPolicy do
  it "selects categories for the Arr app type" do
    policy = described_class.new(
      app_type: "radarr",
      category_ids: [ 2000, 2010, 5000, 8000 ]
    )

    expect(policy.category_ids).to eq([ 2000, 2010 ])
    expect(policy).to be_compatible
    expect(policy).to be_app_filtered
  end

  it "returns all categories for unknown app types" do
    policy = described_class.new(
      app_type: "custom",
      category_ids: [ 2000, 5000, 8000 ]
    )

    expect(policy.category_ids).to eq([ 2000, 5000, 8000 ])
    expect(policy).to be_compatible
    expect(policy).not_to be_app_filtered
  end

  it "does not include tracker-specific supplemental categories automatically" do
    policy = described_class.new(
      app_type: "radarr",
      category_ids: [ 2000, 2010, 8000, 5000 ]
    )

    expect(policy.category_ids).to eq([ 2000, 2010 ])
    expect(policy).to be_compatible
  end

  it "does not use unrelated categories as the only compatibility signal" do
    policy = described_class.new(
      app_type: "radarr",
      category_ids: [ 8000, 5000 ]
    )

    expect(policy.category_ids).to eq([])
    expect(policy).not_to be_compatible
  end

  it "keeps Sonarr anime categories separate" do
    policy = described_class.new(
      app_type: "sonarr",
      category_ids: [ 5000, 5030, 5070, 8000 ]
    )

    expect(policy.category_ids).to eq([ 5000, 5030, 5070 ])
    expect(policy.anime_category_ids).to eq([ 5070 ])
  end

  it "lets custom categories take precedence over automatic categories" do
    policy = described_class.new(
      app_type: "radarr",
      category_ids: [ 5000, 5070 ],
      category_mode: "custom",
      custom_category_ids: [ 2000, 8000 ]
    )

    expect(policy.category_ids).to eq([ 2000, 8000 ])
    expect(policy).to be_compatible
    expect(policy).to be_custom
    expect(policy).to be_manual
  end

  it "derives Sonarr anime categories from custom categories" do
    policy = described_class.new(
      app_type: "sonarr",
      category_ids: [ 5000 ],
      category_mode: "custom",
      custom_category_ids: [ 5000, 5070, 8000 ]
    )

    expect(policy.category_ids).to eq([ 5000, 5070, 8000 ])
    expect(policy.anime_category_ids).to eq([ 5070 ])
  end

  it "uses no categories when category mode is none" do
    policy = described_class.new(
      app_type: "radarr",
      category_ids: [ 2000, 2010 ],
      category_mode: "none"
    )

    expect(policy.category_ids).to eq([])
    expect(policy.anime_category_ids).to eq([])
    expect(policy).to be_compatible
    expect(policy).to be_none
    expect(policy).to be_manual
  end
end
