require "rails_helper"

RSpec.describe "Assignment removal", type: :system do
  before do
    driven_by(:rack_test)

    User.create!(
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    )
  end

  it "removes an assignment with one real form submission without JavaScript" do
    app = ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    assignment = IndexerApp.create!(arr_app: app, indexer:, remote_indexer_id: 42)
    allow(Arr::IndexerDeleteClient).to receive(:call).and_return(
      Arr::IndexerDeleteClient::Result.new(
        success?: true,
        message: "Managed indexer removed.",
        error: nil,
        http_status: 200
      )
    )
    sign_in_through_browser

    visit indexer_apps_path
    click_button "Remove"

    expect(page).to have_current_path(indexer_apps_path)
    expect(page).to have_content("Removed assignment LimeTorrents → Main Radarr")
    expect(page).to have_content("Unassigned")
    expect(IndexerApp.exists?(assignment.id)).to be(false)
    expect(Arr::IndexerDeleteClient).to have_received(:call).once.with(arr_app: app, remote_indexer_id: 42)
  end

  it "refreshes the matrix after the confirmed removal" do
    driven_by(:selenium_headless)
    app = ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
    indexer = Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
    assignment = IndexerApp.create!(arr_app: app, indexer:, remote_indexer_id: 42)
    allow(Arr::IndexerDeleteClient).to receive(:call).and_return(
      Arr::IndexerDeleteClient::Result.new(
        success?: true,
        message: "Managed indexer removed.",
        error: nil,
        http_status: 200
      )
    )
    sign_in_through_browser

    visit indexer_apps_path
    find('input[aria-label="Select LimeTorrents for Main Radarr"]').check
    accept_confirm("Remove this assignment and its managed remote indexer?") do
      click_button "Remove"
    end

    expect(page).to have_current_path(indexer_apps_path)
    expect(page).to have_content("Removed assignment LimeTorrents → Main Radarr")
    expect(page).to have_content("Unassigned")
    expect(page).to have_no_button("Remove")
    expect(IndexerApp.exists?(assignment.id)).to be(false)
    expect(Arr::IndexerDeleteClient).to have_received(:call).once.with(arr_app: app, remote_indexer_id: 42)
  end

  private

    def sign_in_through_browser
      visit new_user_session_path
      fill_in "Email", with: "admin@example.com"
      fill_in "Password", with: "correct-horse-battery-staple"
      click_button "Sign in"
    end
end
