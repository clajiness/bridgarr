require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#format_server_timestamp" do
    around do |example|
      original_tz = ENV["TZ"]
      ENV["TZ"] = "America/Chicago"
      example.run
    ensure
      ENV["TZ"] = original_tz
    end

    it "renders Rails UTC timestamps in the server local timezone" do
      timestamp = Time.zone.parse("2026-07-06 02:35:53 UTC")

      expect(format_server_timestamp(timestamp)).to eq("2026-07-05 21:35:53 CDT")
    end

    it "renders ISO8601 strings in the server local timezone" do
      expect(format_server_timestamp("2026-07-06T02:35:53Z")).to eq("2026-07-05 21:35:53 CDT")
    end
  end
end
