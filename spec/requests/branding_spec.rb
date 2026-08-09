require "rails_helper"

RSpec.describe "Branding", type: :request do
  it "renders the Bridgarr browser and application-shell identity" do
    get root_path

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("title").text).to eq("Dashboard · Bridgarr")
    expect(document.at_css('meta[name="description"]')["content"]).to eq(BrandingHelper::TAGLINE)
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq("#1d140f")
    expect(document.at_css('link[rel="manifest"]')["href"]).to eq(pwa_manifest_path(format: :json))
    expect(document.at_css('link[rel="apple-touch-icon"]')["href"]).to eq("/icon-maskable.png")
    expect(document.at_css("body")["class"]).to include("brand-shell")
    expect(document.at_css("header")["class"]).to include("brand-header")
    expect(document.at_css(".brand-rug-stripe")).to be_present
    expect(document.at_css(".brand-wordmark").text).to eq("Bridgarr")
  end

  it "serves matching installed-app metadata", skip_authentication: true do
    get pwa_manifest_path(format: :json)

    manifest = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(manifest).to include(
      "name" => "Bridgarr",
      "short_name" => "Bridgarr",
      "description" => BrandingHelper::TAGLINE,
      "theme_color" => "#1d140f",
      "background_color" => "#f4ede2"
    )
    expect(manifest.fetch("icons").map { |icon| icon.fetch("src") }).to eq([ "/icon.png", "/icon-maskable.png" ])
  end
end
