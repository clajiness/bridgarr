require "rails_helper"

RSpec.describe Arr::TorznabCategoryPolicy do
  it "selects the Arr schema default categories that Jackett supports" do
    policy = described_class.new(
      app_type: "sonarr",
      arr_default_category_ids: [ 5030, 5040 ],
      jackett_category_ids: [ 5000, 5040, 5045, 5060 ]
    )

    expect(policy.category_ids).to eq([ 5040 ])
    expect(policy.anime_category_ids).to eq([])
    expect(policy).to be_compatible
  end

  it "does not add supported Jackett categories that the Arr schema did not select by default" do
    policy = described_class.new(
      app_type: "sonarr",
      arr_default_category_ids: [ 5030, 5040 ],
      arr_default_anime_category_ids: [],
      jackett_category_ids: [ 5000, 5030, 5040, 5045, 5060, 5070 ]
    )

    expect(policy.category_ids).to eq([ 5030, 5040 ])
    expect(policy.anime_category_ids).to eq([])
  end

  it "uses Radarr schema defaults instead of every movie-related Jackett category" do
    policy = described_class.new(
      app_type: "radarr",
      arr_default_category_ids: [ 2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060 ],
      jackett_category_ids: [ 2000, 2040, 2045, 8000 ]
    )

    expect(policy.category_ids).to eq([ 2000, 2040, 2045 ])
  end

  it "normalizes string IDs and removes duplicates while preserving Arr default order" do
    policy = described_class.new(
      app_type: "sonarr",
      arr_default_category_ids: [ "5030", "5040", "5040" ],
      jackett_category_ids: [ "5040", "5030" ]
    )

    expect(policy.category_ids).to eq([ 5030, 5040 ])
  end

  it "falls back to the app root only when no default categories overlap" do
    policy = described_class.new(
      app_type: "sonarr",
      arr_default_category_ids: [ 5030, 5040 ],
      jackett_category_ids: [ 5000, 5045 ]
    )

    expect(policy.category_ids).to eq([ 5000 ])
    expect(policy).to be_root_fallback
    expect(policy).to be_compatible
  end

  it "does not use unrelated categories as the only compatibility signal" do
    policy = described_class.new(
      app_type: "radarr",
      arr_default_category_ids: [ 2000, 2010 ],
      jackett_category_ids: [ 5000, 8000 ]
    )

    expect(policy.category_ids).to eq([])
    expect(policy.anime_category_ids).to eq([])
    expect(policy).not_to be_compatible
  end

  it "keeps anime defaults separate from ordinary defaults" do
    policy = described_class.new(
      app_type: "sonarr",
      arr_default_category_ids: [ 5030, 5040 ],
      arr_default_anime_category_ids: [ 5070 ],
      jackett_category_ids: [ 5040, 5070, 5080 ]
    )

    expect(policy.category_ids).to eq([ 5040 ])
    expect(policy.anime_category_ids).to eq([ 5070 ])
  end

  it "uses schema defaults for unknown app types when they overlap Jackett" do
    policy = described_class.new(
      app_type: "custom",
      arr_default_category_ids: [ 1000 ],
      jackett_category_ids: [ 1000, 2000 ]
    )

    expect(policy.category_ids).to eq([ 1000 ])
    expect(policy).to be_compatible
    expect(policy).not_to be_app_filtered
  end

  it "lets custom categories take precedence over automatic categories" do
    policy = described_class.new(
      app_type: "radarr",
      arr_default_category_ids: [ 2000, 2010 ],
      jackett_category_ids: [ 2000 ],
      category_mode: "custom",
      custom_category_ids: [ "2000", "8000", "8000" ]
    )

    expect(policy.category_ids).to eq([ 2000, 8000 ])
    expect(policy).to be_compatible
    expect(policy).to be_custom
    expect(policy).to be_manual
  end

  it "derives anime categories from custom categories" do
    policy = described_class.new(
      app_type: "sonarr",
      category_mode: "custom",
      custom_category_ids: [ 5000, 5070, 8000 ]
    )

    expect(policy.category_ids).to eq([ 5000, 5070, 8000 ])
    expect(policy.anime_category_ids).to eq([ 5070 ])
  end

  it "uses no categories when category mode is none" do
    policy = described_class.new(
      app_type: "radarr",
      arr_default_category_ids: [ 2000, 2010 ],
      jackett_category_ids: [ 2000, 2010 ],
      category_mode: "none"
    )

    expect(policy.category_ids).to eq([])
    expect(policy.anime_category_ids).to eq([])
    expect(policy).to be_compatible
    expect(policy).to be_none
    expect(policy).to be_manual
  end
end
