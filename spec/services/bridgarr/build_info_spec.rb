require "rails_helper"

RSpec.describe Bridgarr::BuildInfo do
  around do |example|
    preserve_env("BRIDGARR_VERSION", "BRIDGARR_COMMIT_SHA", "BRIDGARR_BUILD_DATE") do
      example.run
    end
  end

  it "uses development-safe fallbacks when build values are not injected" do
    ENV.delete("BRIDGARR_VERSION")
    ENV.delete("BRIDGARR_COMMIT_SHA")
    ENV.delete("BRIDGARR_BUILD_DATE")

    build_info = described_class.current

    expect(build_info.to_h).to eq(
      version: "development",
      commit_sha: "unknown",
      short_commit_sha: "unknown",
      build_date: "unknown"
    )
  end

  it "exposes injected container build metadata" do
    ENV["BRIDGARR_VERSION"] = "0.1.2"
    ENV["BRIDGARR_COMMIT_SHA"] = "0123456789abcdef"
    ENV["BRIDGARR_BUILD_DATE"] = "2026-07-07T12:34:56Z"

    build_info = described_class.current

    expect(build_info.version).to eq("0.1.2")
    expect(build_info.commit_sha).to eq("0123456789abcdef")
    expect(build_info.short_commit_sha).to eq("0123456789ab")
    expect(build_info.build_date).to eq("2026-07-07T12:34:56Z")
  end

  it "logs startup metadata without requiring a git checkout" do
    ENV["BRIDGARR_VERSION"] = "0.2.0"
    ENV["BRIDGARR_COMMIT_SHA"] = "abcdef1234567890"
    ENV["BRIDGARR_BUILD_DATE"] = "2026-07-07T12:34:56Z"
    logger = instance_spy(ActiveSupport::Logger)

    described_class.log_startup!(logger:)

    expect(logger).to have_received(:info).with(
      message: "Booted Bridgarr",
      bridgarr_version: "0.2.0",
      bridgarr_commit_sha: "abcdef1234567890",
      bridgarr_build_date: "2026-07-07T12:34:56Z"
    )
  end

  def preserve_env(*keys)
    original = keys.to_h { |key| [key, ENV[key]] }
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
