require "rails_helper"

RSpec.describe SyncRunsHelper, type: :helper do
  it "summarizes supported automatic categories without listing every advertised ID" do
    item = SyncRunItem.new(
      category_evidence: {
        category_mode: "auto",
        selected_category_ids: [ 2000, 2010 ],
        selected_anime_category_ids: [],
        jackett_category_ids: [ 2000, 2010, 2040, 8000 ],
        jackett_categories_checked: true,
        root_fallback: false
      }
    )

    expect(sync_category_mismatch_explanation(item)).to include("Jackett reports as supported", "Retry once")
    expect(sync_category_ids_sent(item)).to eq("2000, 2010")
    expect(sync_category_support(item)).to eq("Selected IDs were advertised by Jackett")
    expect(sync_category_selection_basis(item)).to eq("Compatible app defaults")
  end

  it "explains that custom category support was not checked" do
    item = SyncRunItem.new(
      category_evidence: {
        category_mode: "custom",
        selected_category_ids: [ 2000, 8000 ],
        selected_anime_category_ids: []
      }
    )

    expect(sync_category_mismatch_explanation(item)).to include("saved category IDs exactly as entered")
    expect(sync_category_support(item)).to eq("Not checked in Custom mode")
    expect(sync_category_selection_basis(item)).to eq("Saved custom IDs")
  end

  it "explains when no categories were sent" do
    item = SyncRunItem.new(
      category_evidence: {
        category_mode: "none",
        selected_category_ids: [],
        selected_anime_category_ids: []
      }
    )

    expect(sync_category_mismatch_explanation(item)).to include("None mode sent no categories")
    expect(sync_category_ids_sent(item)).to eq("No category IDs")
    expect(sync_category_support(item)).to eq("Not needed in None mode")
  end

  it "hides category details when a stored snapshot is malformed" do
    item = SyncRunItem.new(category_evidence: { category_mode: "unexpected", selected_category_ids: [ 2000 ] })

    expect(sync_category_evidence?(item)).to be(false)
    expect(sync_category_mismatch_explanation(item)).to include("retry once before changing")
  end
end
