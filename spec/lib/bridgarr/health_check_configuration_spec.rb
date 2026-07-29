require "rails_helper"
require "open3"

RSpec.describe Bridgarr::HealthCheckConfiguration do
  describe ".jackett_indexer_timeout_seconds" do
    around do |example|
      original_value = ENV.delete("JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS")
      example.run
    ensure
      ENV["JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS"] = original_value if original_value
    end

    it "defaults to 120 seconds and accepts a positive integer" do
      expect(described_class.jackett_indexer_timeout_seconds).to eq(120)
      expect(described_class.jackett_indexer_timeout_seconds("45")).to eq(45)
    end

    it "accepts only canonical unpadded ASCII decimal positive integers" do
      [ " 30 ", "1_0", "+30", "0", "-1", "1.5", "abc" ].each do |value|
        expect do
          described_class.jackett_indexer_timeout_seconds(value)
        end.to raise_error(
          Bridgarr::HealthCheckConfiguration::ConfigurationError,
          /JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS must be a positive integer/
        )
      end
    end

    it "stops application startup with a clear error for an invalid timeout" do
      stdout, stderr, status = Open3.capture3(
        {
          "RAILS_ENV" => "test",
          "JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS" => "abc"
        },
        Rails.root.join("bin/rails").to_s,
        "runner",
        "true",
        chdir: Rails.root.to_s
      )

      expect(status).not_to be_success
      expect("#{stdout}\n#{stderr}").to include(
        'JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS must be a positive integer; received "abc"'
      )
    end
  end
end
