require "rails_helper"

RSpec.describe "Indexer app assignments", type: :request do
  let(:arr_app) do
    ArrApp.create!(
      name: "Main Radarr",
      app_type: "radarr",
      base_url: "http://localhost:7878",
      api_key: "radarr-api-key"
    )
  end

  let(:indexer) do
    Indexer.create!(name: "LimeTorrents", jackett_id: "limetorrents")
  end

  let(:assignment) do
    IndexerApp.create!(arr_app:, indexer:)
  end

  it "renders assignment settings" do
    get edit_indexer_app_path(assignment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assignment settings")
    expect(response.body).to include("Connection mode")
    expect(response.body).to include("Category mode")
    expect(response.body).to include("LimeTorrents")
    expect(response.body).to include("Main Radarr")
  end

  it "updates assignment category settings" do
    patch indexer_app_path(assignment), params: {
      indexer_app: {
        connection_mode: "bridged",
        category_mode: "custom",
        custom_categories: "2000, 8000"
      }
    }

    expect(response).to redirect_to(indexer_path(indexer))
    expect(flash[:notice]).to eq("Assignment settings saved.")
    expect(assignment.reload.connection_mode).to eq("bridged")
    expect(assignment.reload.category_mode).to eq("custom")
    expect(assignment.custom_categories).to eq("2000,8000")
  end

  it "returns to the app page when editing from an app" do
    patch indexer_app_path(assignment), params: {
      return_to: "arr_app",
      indexer_app: {
        category_mode: "none"
      }
    }

    expect(response).to redirect_to(arr_app_path(arr_app))
    expect(assignment.reload.category_mode).to eq("none")
  end

  it "shows invalid custom category errors" do
    patch indexer_app_path(assignment), params: {
      indexer_app: {
        category_mode: "custom",
        custom_categories: "movies"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be a comma-separated list of positive category IDs")
  end
end
