require "rails_helper"

RSpec.describe "Arr apps", type: :request do
  let(:arr_app) do
    ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
  end

  it "renders the apps index" do
    arr_app

    get arr_apps_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main Sonarr")
    expect(response.body).to include("Not tested")
    expect(response.body).to include("Test all")
  end

  it "renders the empty apps state" do
    get arr_apps_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add Sonarr, Radarr, or friends so Bridgarr knows where to send indexers.")
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
    arr_app

    get arr_app_path(arr_app)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main Sonarr")
    expect(response.body).to include("Test connection")
  end

  it "tests an app connection" do
    arr_app
    result = Arr::ConnectionTest::Result.new(
      success?: true,
      message: "Sonarr connection works.",
      error: nil,
      http_status: 200,
      app_name: "Sonarr",
      version: "4.0.0"
    )
    allow(Arr::ConnectionTest).to receive(:call).and_return(result)

    post test_connection_arr_app_path(arr_app)

    expect(response).to redirect_to(arr_app_path(arr_app))
    expect(Arr::ConnectionTest).to have_received(:call).with(
      base_url: "http://localhost:8989",
      api_key: "sonarr-api-key"
    )
    expect(flash[:notice]).to eq("Main Sonarr connection works.")
    expect(arr_app.reload.last_status).to eq("ok")
    expect(arr_app.last_error).to be_nil
    expect(arr_app.last_tested_at).to be_present
  end

  it "tests an app connection from the apps table" do
    arr_app
    result = Arr::ConnectionTest::Result.new(
      success?: true,
      message: "Sonarr connection works.",
      error: nil,
      http_status: 200,
      app_name: "Sonarr",
      version: "4.0.0"
    )
    allow(Arr::ConnectionTest).to receive(:call).and_return(result)

    post test_connection_arr_app_path(arr_app), params: { return_to: "index" }

    expect(response).to redirect_to(arr_apps_path)
    expect(flash[:notice]).to eq("Main Sonarr connection works.")
    expect(arr_app.reload.last_status).to eq("ok")
  end

  it "tests all app connections" do
    arr_app
    radarr = ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
    success = Arr::ConnectionTest::Result.new(
      success?: true,
      message: "Sonarr connection works.",
      error: nil,
      http_status: 200,
      app_name: "Sonarr",
      version: "4.0.0"
    )
    failure = Arr::ConnectionTest::Result.new(
      success?: false,
      message: "App returned HTTP 401. Check the URL and API key.",
      error: "App returned HTTP 401. Check the URL and API key.",
      http_status: 401,
      app_name: nil,
      version: nil
    )
    allow(Arr::ConnectionTest).to receive(:call).and_return(success, failure)

    post test_connections_arr_apps_path

    expect(response).to redirect_to(arr_apps_path)
    expect(flash[:notice]).to eq("1 app connected, 1 failed.")
    expect(radarr.reload.last_status).to eq("ok")
    expect(arr_app.reload.last_status).to eq("error")
  end

  it "shows failed app connection tests" do
    arr_app
    result = Arr::ConnectionTest::Result.new(
      success?: false,
      message: "App returned HTTP 401. Check the URL and API key.",
      error: "App returned HTTP 401. Check the URL and API key.",
      http_status: 401,
      app_name: nil,
      version: nil
    )
    allow(Arr::ConnectionTest).to receive(:call).and_return(result)

    post test_connection_arr_app_path(arr_app)

    expect(response).to redirect_to(arr_app_path(arr_app))
    expect(flash[:alert]).to eq("App returned HTTP 401. Check the URL and API key.")
    expect(arr_app.reload.last_status).to eq("error")
    expect(arr_app.last_error).to eq("App returned HTTP 401. Check the URL and API key.")
  end

  it "renders the edit app page" do
    arr_app

    get edit_arr_app_path(arr_app)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Edit app")
  end

  it "updates an app" do
    arr_app

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
    arr_app

    expect {
      delete arr_app_path(arr_app)
    }.to change(ArrApp, :count).by(-1)

    expect(response).to redirect_to(arr_apps_path)
  end
end
