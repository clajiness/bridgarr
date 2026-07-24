require "rails_helper"

RSpec.describe "Administrator authentication", type: :system do
  before do
    driven_by(:rack_test)
  end

  let(:password) { "correct-horse-battery-staple" }

  it "shows read-only provisioning instructions until the CLI creates an administrator" do
    visit root_path

    expect(page).to have_current_path(new_admin_setup_path)
    expect(page).to have_content("Provisioning required")
    expect(page).to have_content("docker compose exec bridgarr bin/rails bridgarr:admin:create")
    expect(page).to have_no_button("Create administrator")

    create_administrator
    visit root_path
    expect(page).to have_current_path(new_user_session_path)
  end

  it "signs an existing administrator in and preserves the requested destination" do
    create_administrator

    visit arr_apps_path
    expect(page).to have_current_path(new_user_session_path)

    fill_in "Email", with: "admin@example.com"
    fill_in "Password", with: password
    click_button "Sign in"

    expect(page).to have_current_path(arr_apps_path)
    expect(page).to have_content("Apps")
  end

  it "locks repeated failed authentication and unlocks after the configured interval" do
    user = create_administrator
    visit new_user_session_path

    Devise.maximum_attempts.times do
      fill_in "Email", with: user.email
      fill_in "Password", with: "incorrect-password"
      click_button "Sign in"
    end

    expect(user.reload).to be_access_locked

    travel(Devise.unlock_in + 1.second) do
      fill_in "Email", with: user.email
      fill_in "Password", with: password
      click_button "Sign in"

      expect(page).to have_current_path(root_path)
    end
  end

  it "requires a new sign-in after inactivity" do
    create_administrator
    sign_in_through_browser

    travel(Devise.timeout_in + 1.second) do
      visit arr_apps_path

      expect(page).to have_current_path(new_user_session_path)
      expect(page).to have_content("session expired")
    end
  end

  private

    def create_administrator
      User.create!(
        email: "admin@example.com",
        password:,
        password_confirmation: password,
        local_admin_slot: User::LOCAL_ADMIN_SLOT
      )
    end

    def sign_in_through_browser
      visit new_user_session_path
      fill_in "Email", with: "admin@example.com"
      fill_in "Password", with: password
      click_button "Sign in"
    end
end
