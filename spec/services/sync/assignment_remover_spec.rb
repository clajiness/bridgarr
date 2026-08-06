require "rails_helper"

RSpec.describe Sync::AssignmentRemover do
  class FakeAssignmentDeleteClient
    Result = Data.define(:success?, :message, :error, :http_status)

    class << self
      attr_accessor :result
      attr_reader :calls
    end

    def self.call(**attributes)
      @calls ||= []
      @calls << attributes
      result
    end

    def self.reset!
      @calls = []
      @result = Result.new(success?: true, message: "Removed.", error: nil, http_status: 200)
    end
  end

  let(:arr_app) do
    ArrApp.create!(name: "Sonarr", app_type: "sonarr", base_url: "http://localhost:8989", api_key: "key")
  end

  let(:indexer) { Indexer.create!(name: "EZTV", jackett_id: "eztv") }

  before { FakeAssignmentDeleteClient.reset! }

  it "removes an unsynced local assignment without a remote request" do
    assignment = IndexerApp.create!(arr_app:, indexer:)

    result = described_class.call(indexer_app: assignment, delete_client: FakeAssignmentDeleteClient)

    expect(result).to be_success
    expect(IndexerApp.exists?(assignment.id)).to be(false)
    expect(FakeAssignmentDeleteClient.calls).to be_empty
  end

  it "removes the associated remote indexer before deleting the assignment" do
    assignment = IndexerApp.create!(arr_app:, indexer:, remote_indexer_id: 42)

    result = described_class.call(indexer_app: assignment, delete_client: FakeAssignmentDeleteClient)

    expect(result).to be_success
    expect(FakeAssignmentDeleteClient.calls).to contain_exactly(arr_app:, remote_indexer_id: 42)
    expect(IndexerApp.exists?(assignment.id)).to be(false)
  end

  it "preserves the assignment when remote deletion fails" do
    assignment = IndexerApp.create!(arr_app:, indexer:, remote_indexer_id: 42)
    FakeAssignmentDeleteClient.result = FakeAssignmentDeleteClient::Result.new(
      success?: false,
      message: "HTTP 500 apikey=remote-secret",
      error: "HTTP 500 apikey=remote-secret",
      http_status: 500
    )

    result = described_class.call(indexer_app: assignment, delete_client: FakeAssignmentDeleteClient)

    expect(result).not_to be_success
    expect(result.message).not_to include("remote-secret")
    expect(IndexerApp.exists?(assignment.id)).to be(true)
  end

  it "does not remove an assignment while its sync is active" do
    assignment = IndexerApp.create!(arr_app:, indexer:, remote_indexer_id: 42)
    sync_run = SyncRun.create!(status: "running", total_count: 1)
    sync_run.sync_run_items.create!(indexer_app: assignment, status: "running")

    result = described_class.call(indexer_app: assignment, delete_client: FakeAssignmentDeleteClient)

    expect(result).not_to be_success
    expect(result.message).to include("active assignment sync")
    expect(FakeAssignmentDeleteClient.calls).to be_empty
    expect(IndexerApp.exists?(assignment.id)).to be(true)
  end
end
