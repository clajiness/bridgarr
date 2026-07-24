require "rails_helper"
require "open3"

RSpec.describe Bridgarr::AuthenticationConfiguration do
  describe ".session_timeout_minutes" do
    it "accepts a positive integer" do
      expect(described_class.session_timeout_minutes("45")).to eq(45)
    end

    it "accepts only canonical unpadded ASCII decimal positive integers" do
      expect(described_class.session_timeout_minutes("30")).to eq(30)

      [ " 30 ", "1_0", "+30", "0", "-1", "1.5", "garbage" ].each do |value|
        expect do
          described_class.session_timeout_minutes(value)
        end.to raise_error(
          Bridgarr::AuthenticationConfiguration::ConfigurationError,
          /AUTH_SESSION_TIMEOUT_MINUTES must be a positive integer/
        )
      end
    end

    it "stops application startup with a clear error for an invalid timeout" do
      stdout, stderr, status = Open3.capture3(
        {
          "RAILS_ENV" => "test",
          "AUTH_SESSION_TIMEOUT_MINUTES" => "invalid"
        },
        Rails.root.join("bin/rails").to_s,
        "runner",
        "true",
        chdir: Rails.root.to_s
      )

      expect(status).not_to be_success
      expect("#{stdout}\n#{stderr}").to include(
        "AUTH_SESSION_TIMEOUT_MINUTES must be a positive integer; received \"invalid\""
      )
    end
  end

  describe ".trusted_proxies" do
    it "trusts no forwarding proxy when none is explicitly configured" do
      expect(described_class.trusted_proxies("")).to eq(described_class::NO_TRUSTED_PROXIES)
    end

    it "parses explicitly trusted IP addresses and CIDR ranges" do
      expect(described_class.trusted_proxies("10.0.0.5, 172.20.0.0/16")).to eq(
        [
          IPAddr.new("10.0.0.5"),
          IPAddr.new("172.20.0.0/16")
        ]
      )
    end

    it "rejects an invalid trusted proxy configuration" do
      expect do
        described_class.trusted_proxies("not-a-network")
      end.to raise_error(
        Bridgarr::AuthenticationConfiguration::ConfigurationError,
        /TRUSTED_PROXY_CIDRS/
      )
    end

    it "uses a forwarded client IP only when the connecting proxy is trusted" do
      app = lambda do |env|
        request = ActionDispatch::Request.new(env)
        [ 200, {}, [ request.remote_ip.to_s ] ]
      end
      middleware = ActionDispatch::RemoteIp.new(
        app,
        true,
        described_class.trusted_proxies("10.0.0.0/8")
      )
      env = Rack::MockRequest.env_for(
        "/",
        "REMOTE_ADDR" => "10.1.2.3",
        "HTTP_X_FORWARDED_FOR" => "198.51.100.42"
      )

      _status, _headers, body = middleware.call(env)

      expect(body.join).to eq("198.51.100.42")
    end
  end
end
