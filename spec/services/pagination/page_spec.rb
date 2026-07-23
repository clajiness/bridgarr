require "rails_helper"

RSpec.describe Pagination::Page do
  it "paginates Active Record relations and clamps pages past the end" do
    12.times do |index|
      SyncRun.create!(status: "succeeded", started_at: Time.current + index.seconds)
    end

    page = described_class.new(
      collection: SyncRun.order(started_at: :desc),
      page: 99,
      per_page: 10
    )

    expect(page).to have_attributes(
      current_page: 2,
      per_page: 10,
      total_count: 12,
      total_pages: 2,
      first_item_number: 11,
      last_item_number: 12
    )
    expect(page.records.size).to eq(2)
    expect(page).to be_previous_page
    expect(page).not_to be_next_page
  end

  it "paginates arrays and rejects unsupported page sizes" do
    page = described_class.new(
      collection: (1..30).to_a,
      page: 2,
      per_page: 999,
      default_page_size: 25
    )

    expect(page).to have_attributes(current_page: 2, per_page: 25, total_count: 30, total_pages: 2)
    expect(page.records).to eq((26..30).to_a)
  end
end
