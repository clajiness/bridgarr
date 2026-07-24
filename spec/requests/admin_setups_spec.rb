require "rails_helper"

RSpec.describe "Administrator setup", type: :request, skip_authentication: true do
  let(:valid_attributes) do
    {
      email: "admin@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple",
      local_admin_slot: User::LOCAL_ADMIN_SLOT
    }
  end

  it "renders read-only provisioning instructions when no administrator exists" do
    get new_admin_setup_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Administrator provisioning required")
    expect(response.body).to include("docker compose exec bridgarr bin/rails bridgarr:admin:create")
    expect(response.body).not_to include("<form")
  end

  it "redirects the sign-in page to setup before an administrator exists" do
    get new_user_session_path

    expect(response).to redirect_to(new_admin_setup_path)
  end

  it "closes setup after an administrator exists" do
    User.create!(valid_attributes)

    get new_admin_setup_path

    expect(response).to redirect_to(new_user_session_path)
  end

  it "does not expose an HTTP route that can create an administrator" do
    expect do
      Rails.application.routes.recognize_path("/setup", method: :post)
    end.to raise_error(ActionController::RoutingError)
  end

  it "redirects an authenticated administrator away from setup" do
    user = User.create!(valid_attributes)
    sign_in(user)

    get new_admin_setup_path

    expect(response).to redirect_to(root_path)
  end

  it "still requires local provisioning when only a future non-local user exists" do
    User.create!(
      email: "oidc-placeholder@example.com",
      password: "correct-horse-battery-staple",
      password_confirmation: "correct-horse-battery-staple"
    )

    get root_path

    expect(response).to redirect_to(new_admin_setup_path)
  end

  it "does not expose Devise registration routes" do
    expect do
      Rails.application.routes.recognize_path("/users", method: :post)
    end.to raise_error(ActionController::RoutingError)
    expect do
      Rails.application.routes.recognize_path("/users/sign_up", method: :get)
    end.to raise_error(ActionController::RoutingError)
  end
end
