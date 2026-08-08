require "rails_helper"

RSpec.describe Sync::ErrorClassifier do
  it "classifies timeout errors as retryable" do
    result = described_class.call("Could not connect to Sonarr: Net::ReadTimeout with #<TCPSocket:(closed)>")

    expect(result.kind).to eq("timeout")
    expect(result).to be_retryable
  end

  it "classifies category mismatches as non-retryable" do
    result = described_class.call("Query successful, but no results in the configured categories were returned from your indexer.")

    expect(result.kind).to eq("category_mismatch")
    expect(result).not_to be_retryable
  end

  it "classifies incompatible category skips" do
    result = described_class.call("No compatible default categories were found for EZTV.", skipped: true)

    expect(result.kind).to eq("incompatible_categories")
    expect(result).not_to be_retryable
  end

  it "classifies authentication errors" do
    result = described_class.call("Radarr returned HTTP 401 Unauthorized.")

    expect(result.kind).to eq("authentication")
    expect(result).not_to be_retryable
  end

  it "classifies stale reconciliation plans as actionable and non-retryable" do
    result = described_class.call("The reconciliation plan changed before the job started.")

    expect(result.kind).to eq("stale_plan")
    expect(result.recommendation).to include("Preview reconciliation again")
    expect(result).not_to be_retryable
  end

  it "classifies unmanaged remote overlaps" do
    result = described_class.call("A potentially overlapping unmanaged indexer exists as remote ID 42. Preview reconciliation and repair the association.")

    expect(result.kind).to eq("remote_conflict")
    expect(result.recommendation).to include("explicitly repair")
    expect(result).not_to be_retryable
  end

  it "classifies orphaned remote associations" do
    result = described_class.call("Remote indexer ID 42 no longer exists. Preview reconciliation and forget or repair the stale association.")

    expect(result.kind).to eq("orphaned")
    expect(result.recommendation).to include("forget the stale association")
    expect(result).not_to be_retryable
  end

  it "classifies challenge solver timeouts as retryable" do
    result = described_class.call("FlareSolverr was unable to process the request. Error solving the challenge. Timeout after 55.0 seconds.")

    expect(result.kind).to eq("challenge_solver_timeout")
    expect(result.summary).to eq("The anti-bot challenge solver could not complete the indexer request before the validation timeout.")
    expect(result).to be_retryable
  end

  it "classifies a destination SQLite lock as retryable" do
    result = described_class.call("Lidarr returned HTTP 500 while trying to update an indexer. database is locked")

    expect(result.kind).to eq("destination_database_busy")
    expect(result.summary).to eq("The destination Arr application's database was temporarily busy.")
    expect(result.recommendation).to include("destination application becomes idle", "competing app instances")
    expect(result).to be_retryable
  end

  it "recognizes SQLite busy and locked result names" do
    expect(described_class.call("SQLITE_BUSY_TIMEOUT").kind).to eq("destination_database_busy")
    expect(described_class.call("SQLITE_LOCKED_SHAREDCACHE").kind).to eq("destination_database_busy")
  end
end
