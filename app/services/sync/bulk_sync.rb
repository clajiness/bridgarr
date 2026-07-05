module Sync
  class BulkSync
    def self.call(scope: eligible_assignments)
      new(scope:).call
    end

    def self.eligible_assignments
      IndexerApp
        .includes(:indexer, :arr_app)
        .joins(:indexer, :arr_app)
        .where(indexers: { enabled: true }, arr_apps: { enabled: true })
        .order("indexers.name", "arr_apps.name")
    end

    def initialize(scope:)
      @scope = scope
    end

    def call
      SyncRun.transaction do
        sync_run = SyncRun.create!(mode: "bulk", status: "queued")
        scope.each do |indexer_app|
          sync_run.sync_run_items.create!(indexer_app:)
        end
        sync_run.update!(total_count: sync_run.sync_run_items.count)
        Sync::BulkSyncJob.perform_later(sync_run.id)
        sync_run
      end
    end

    private

      attr_reader :scope
  end
end
