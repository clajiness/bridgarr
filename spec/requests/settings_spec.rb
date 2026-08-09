require "rails_helper"

RSpec.describe "Settings", type: :request do
  around do |example|
    preserve_env("BRIDGARR_VERSION", "BRIDGARR_COMMIT_SHA", "BRIDGARR_BUILD_DATE") do
      example.run
    end
  end

  it "renders the settings page" do
    get settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bridgarr URL")
    expect(response.body).to include("Jackett URL")
    expect(response.body).to include("Build info")
    document = Nokogiri::HTML(response.body)
    main_column = document.at_css('[data-settings-column="main"]')
    sidebar = document.at_css('[data-settings-column="sidebar"]')
    expect(main_column.text).to include(
      "Connection settings",
      "Bridged proxy authentication",
      "Discover indexers again before syncing"
    )
    expect(sidebar.text).to include("Jackett connection", "Build info")
  end

  it "renders injected build identity" do
    ENV["BRIDGARR_VERSION"] = "0.2.0"
    ENV["BRIDGARR_COMMIT_SHA"] = "abcdef1234567890"
    ENV["BRIDGARR_BUILD_DATE"] = "2026-07-07T12:34:56Z"

    get settings_path

    expect(response.body).to include("0.2.0")
    expect(response.body).to include("abcdef123456")
    expect(response.body).to include("2026-07-07T12:34:56Z")
    expect(response.body).not_to include("7890</dd>")
  end

  it "updates connection settings" do
    patch settings_path, params: {
      settings: {
        bridgarr_base_url: "http://localhost:3000",
        jackett_base_url: "http://localhost:9117",
        jackett_api_key: "jackett-api-key"
      }
    }

    expect(response).to redirect_to(settings_path)
    expect(Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY)).to eq("http://localhost:3000")
    expect(Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)).to eq("http://localhost:9117")
    expect(Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)).to eq("jackett-api-key")
  end

  it "rolls back every connection setting when one value cannot be saved" do
    Setting.write_value(Setting::BRIDGARR_BASE_URL_KEY, "http://original-bridgarr:9697")
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://original-jackett:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "original-key")
    allow(Setting).to receive(:write_value).and_call_original
    allow(Setting).to receive(:write_value)
      .with(Setting::JACKETT_API_KEY_KEY, "replacement-key")
      .and_raise(ActiveRecord::RecordInvalid.new(Setting.new))

    patch settings_path, params: {
      settings: {
        bridgarr_base_url: "http://replacement-bridgarr:9697",
        jackett_base_url: "http://replacement-jackett:9117",
        jackett_api_key: "replacement-key"
      }
    }

    expect(response).to redirect_to(settings_path)
    expect(flash[:alert]).to include("Could not save connection settings")
    expect(Setting.fetch_value(Setting::BRIDGARR_BASE_URL_KEY)).to eq("http://original-bridgarr:9697")
    expect(Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)).to eq("http://original-jackett:9117")
    expect(Setting.fetch_value(Setting::JACKETT_API_KEY_KEY)).to eq("original-key")
  end

  it "does not change connection settings while an assignment sync is active" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://original-jackett:9117")
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    assignment = IndexerApp.create!(arr_app:, indexer:)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    patch settings_path, params: {
      settings: {
        bridgarr_base_url: "http://replacement-bridgarr:9697",
        jackett_base_url: "http://replacement-jackett:9117",
        jackett_api_key: "replacement-key"
      }
    }

    expect(response).to redirect_to(settings_path)
    expect(flash[:alert]).to include("active assignment syncs")
    expect(Setting.fetch_value(Setting::JACKETT_BASE_URL_KEY)).to eq("http://original-jackett:9117")
  end

  it "tracks Jackett API key rotations without treating an unchanged save as a rotation" do
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "original-key")

    patch settings_path, params: {
      settings: {
        bridgarr_base_url: "http://localhost:3000",
        jackett_base_url: "http://localhost:9117",
        jackett_api_key: "original-key"
      }
    }

    expect(Setting.jackett_api_key_version).to eq(1)

    patch settings_path, params: {
      settings: {
        bridgarr_base_url: "http://localhost:3000",
        jackett_base_url: "http://localhost:9117",
        jackett_api_key: "rotated-key"
      }
    }

    expect(Setting.jackett_api_key_version).to eq(2)
  end

  it "tests the saved Jackett connection" do
    Setting.write_value(Setting::JACKETT_BASE_URL_KEY, "http://localhost:9117")
    Setting.write_value(Setting::JACKETT_API_KEY_KEY, "jackett-api-key")

    result = Jackett::ConnectionTest::Result.new(
      success?: true,
      message: "Jackett connection works.",
      error: nil,
      http_status: 200
    )
    allow(Jackett::ConnectionTest).to receive(:call).and_return(result)

    post test_jackett_settings_path

    expect(response).to redirect_to(settings_path)
    expect(Jackett::ConnectionTest).to have_received(:call).with(
      base_url: "http://localhost:9117",
      api_key: "jackett-api-key"
    )
    expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("ok")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)).to eq("")
  end

  it "redacts secrets from failed Jackett connection flashes" do
    result = Jackett::ConnectionTest::Result.new(
      success?: false,
      message: "GET /api?apikey=visible-secret Authorization: Bearer auth-secret failed",
      error: "GET /api?apikey=visible-secret Authorization: Bearer auth-secret failed",
      http_status: nil
    )
    allow(Jackett::ConnectionTest).to receive(:call).and_return(result)

    post test_jackett_settings_path

    expect(flash[:alert]).to include("apikey=[REDACTED]", "Bearer [REDACTED]")
    expect(flash[:alert]).not_to include("visible-secret", "auth-secret")
  end

  it "records and reports an unexpected Jackett connection-test failure" do
    allow(Jackett::ConnectionTest).to receive(:call).and_raise(StandardError, "unexpected token=secret-value")

    post test_jackett_settings_path

    expect(response).to redirect_to(settings_path)
    expect(flash[:alert]).to eq("Unexpected Jackett connection-test failure: unexpected token=[REDACTED]")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_STATUS_KEY)).to eq("error")
    expect(Setting.fetch_value(Setting::JACKETT_LAST_ERROR_KEY)).to eq(flash[:alert])
  end

  it "shows the saved Jackett connection status" do
    Setting.write_value(Setting::JACKETT_LAST_STATUS_KEY, "ok")
    Setting.write_value(Setting::JACKETT_LAST_TESTED_AT_KEY, "2026-07-04T12:00:00Z")

    get settings_path

    expect(response.body).to include("Connected")
    expect(response.body).to include(Time.iso8601("2026-07-04T12:00:00Z").localtime.strftime("%Y-%m-%d %H:%M:%S %Z"))
    connected_badge = Nokogiri::HTML(response.body).css("span").find { |node| node.text.strip == "Connected" }
    expect(connected_badge["class"]).to include("bg-green-50", "text-green-800")
  end

  it "rotates the bridged proxy API key" do
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "old-proxy-key")
    Setting.write_value(Setting::PROXY_API_KEY_VERSION_KEY, 1)
    allow(SecureRandom).to receive(:hex).and_call_original
    allow(SecureRandom).to receive(:hex).with(32).and_return("new-proxy-key")

    post rotate_proxy_api_key_settings_path

    expect(response).to redirect_to(settings_path)
    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("new-proxy-key")
    expect(Setting.proxy_api_key_version).to eq(2)
    expect(flash[:notice]).to include("Preview and apply all bridged assignments")
  end

  it "does not rotate the proxy API key while an assignment sync is active" do
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "old-proxy-key")
    Setting.write_value(Setting::PROXY_API_KEY_VERSION_KEY, 1)
    arr_app = ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://sonarr:8989", api_key: "key")
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    assignment = IndexerApp.create!(arr_app:, indexer:, connection_mode: "bridged")
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    post rotate_proxy_api_key_settings_path

    expect(response).to redirect_to(settings_path)
    expect(flash[:alert]).to include("active assignment syncs")
    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("old-proxy-key")
    expect(Setting.proxy_api_key_version).to eq(1)
  end

  it "reports a proxy-key persistence failure without losing the current key" do
    Setting.write_value(Setting::PROXY_API_KEY_KEY, "old-proxy-key")
    Setting.write_value(Setting::PROXY_API_KEY_VERSION_KEY, 1)
    allow(Setting).to receive(:rotate_proxy_api_key!)
      .and_raise(ActiveRecord::StatementInvalid, "database token=visible-secret is busy")

    post rotate_proxy_api_key_settings_path

    expect(response).to redirect_to(settings_path)
    expect(flash[:alert]).to eq("Could not rotate the proxy API key: database token=[REDACTED] is busy")
    expect(Setting.fetch_value(Setting::PROXY_API_KEY_KEY)).to eq("old-proxy-key")
    expect(Setting.proxy_api_key_version).to eq(1)
  end

  it "warns when bridged assignments require the new proxy key" do
    arr_app = ArrApp.create!(
      name: "Main Sonarr",
      app_type: "sonarr",
      base_url: "http://sonarr:8989",
      api_key: "arr-api-key"
    )
    indexer = Indexer.create!(name: "EZTV", jackett_id: "eztv")
    IndexerApp.create!(
      arr_app:,
      indexer:,
      connection_mode: "bridged",
      remote_indexer_id: 42,
      proxy_api_key_version: 1
    )
    Setting.write_value(Setting::PROXY_API_KEY_VERSION_KEY, 2)

    get settings_path

    expect(response.body).to include("proxy API key changed")
  end

  def preserve_env(*keys)
    original = keys.to_h { |key| [ key, ENV[key] ] }
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
