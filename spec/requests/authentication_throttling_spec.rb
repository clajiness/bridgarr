require "rails_helper"

RSpec.describe "Authentication throttling", type: :request, skip_authentication: true do
  let!(:user) do
    User.create!(
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    )
  end

  it "throttles sign-in attempts by normalized account identifier" do
    AuthenticationRateLimited::ACCOUNT_LIMIT.times do |attempt|
      email = attempt.even? ? " ADMIN@EXAMPLE.COM " : "admin@example.com"
      post user_session_path, params: { user: { email:, password: "incorrect-password" } }
    end

    post user_session_path, params: {
      user: { email: "Admin@Example.com", password: "incorrect-password" }
    }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("Too many authentication attempts. Try again later.")
  end

  it "throttles password recovery by source IP across different identifiers" do
    AuthenticationRateLimited::SOURCE_IP_LIMIT.times do |attempt|
      post user_password_path,
        params: { user: { email: "unknown-#{attempt}@example.com" } },
        headers: {
          "REMOTE_ADDR" => "198.51.100.24",
          "HTTP_X_FORWARDED_FOR" => "203.0.113.#{attempt + 1}"
        }
    end

    post user_password_path,
      params: { user: { email: "another-unknown@example.com" } },
      headers: {
        "REMOTE_ADDR" => "198.51.100.24",
        "HTTP_X_FORWARDED_FOR" => "192.0.2.55"
      }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(new_user_password_path)
    expect(flash[:alert]).to eq("Too many authentication attempts. Try again later.")
  end

  it "normalizes password-recovery identifiers before applying the account limit" do
    AuthenticationRateLimited::ACCOUNT_LIMIT.times do |attempt|
      email = attempt.even? ? " UNKNOWN@EXAMPLE.COM " : "unknown@example.com"
      post user_password_path,
        params: { user: { email: } },
        headers: { "REMOTE_ADDR" => "198.51.100.#{attempt + 1}" }
    end

    post user_password_path,
      params: { user: { email: "Unknown@Example.com" } },
      headers: { "REMOTE_ADDR" => "203.0.113.10" }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(new_user_password_path)
    expect(flash[:alert]).to eq("Too many authentication attempts. Try again later.")
  end

  it "returns the same recovery response whether or not the account exists" do
    post user_password_path, params: { user: { email: user.email } }
    existing_response = [ response.status, response.location, flash[:notice] ]

    post user_password_path, params: { user: { email: "unknown@example.com" } }
    missing_response = [ response.status, response.location, flash[:notice] ]

    expect(existing_response).to eq(missing_response)
    expect(existing_response.last).to eq(I18n.t("devise.passwords.send_paranoid_instructions"))
  end
end
