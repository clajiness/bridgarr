require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  it "renders the dashboard" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard")
  end
end
