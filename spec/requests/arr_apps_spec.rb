require "rails_helper"

RSpec.describe "Arr apps", type: :request do
  let!(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  it "renders the apps index" do
    get arr_apps_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main Sonarr")
  end

  it "renders the new app page" do
    get new_arr_app_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Application")
  end

  it "creates an app" do
    expect {
      post arr_apps_path, params: {
        arr_app: {
          name: "Main Lidarr",
          app_type: "lidarr",
          base_url: "http://localhost:8686",
          api_key: "lidarr-api-key",
          enabled: true
        }
      }
    }.to change(ArrApp, :count).by(1)

    expect(response).to redirect_to(arr_app_path(ArrApp.last))
  end

  it "shows an app" do
    get arr_app_path(arr_app)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main Sonarr")
  end

  it "renders the edit app page" do
    get edit_arr_app_path(arr_app)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Edit app")
  end

  it "updates an app" do
    patch arr_app_path(arr_app), params: {
      arr_app: {
        name: "Updated Sonarr",
        app_type: arr_app.app_type,
        base_url: arr_app.base_url,
        api_key: arr_app.api_key,
        enabled: arr_app.enabled
      }
    }

    expect(response).to redirect_to(arr_app_path(arr_app))
    expect(arr_app.reload.name).to eq("Updated Sonarr")
  end

  it "destroys an app" do
    expect {
      delete arr_app_path(arr_app)
    }.to change(ArrApp, :count).by(-1)

    expect(response).to redirect_to(arr_apps_path)
  end
end
