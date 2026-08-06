module Sync
  class BulkSync
    def self.call(scope: eligible_assignments, plan_items: nil)
      new(scope:, plan_items:).call
    end

    def self.eligible_assignments
      IndexerApp
        .includes(:indexer, :arr_app)
        .joins(:indexer, :arr_app)
        .where(indexers: { enabled: true }, arr_apps: { enabled: true })
        .order("indexers.name", "arr_apps.name")
    end

    def initialize(scope:, plan_items:)
      @scope = scope
      @plan_items_by_assignment_id = Array(plan_items).index_by { |item| item.indexer_app.id }
    end

    def call
      sync_run = SyncRun.transaction do
        sync_run = SyncRun.create!(mode: "bulk", status: "queued")
        scope.each do |indexer_app|
          indexer_app.with_lock do
            next if indexer_app.active_sync?

            plan_item = plan_items_by_assignment_id[indexer_app.id]
            sync_run.sync_run_items.create!(
              indexer_app:,
              indexer_name: indexer_app.indexer.name,
              arr_app_name: indexer_app.arr_app.name,
              planned_action: plan_item&.state,
              plan_digest: plan_item&.plan_digest,
              plan_changes: plan_item ? JSON.generate(plan_item.changes) : nil
            )
          end
        end
        total_count = sync_run.sync_run_items.count
        attributes = { total_count: }
        attributes.merge!(status: "skipped", finished_at: Time.current) if total_count.zero?
        sync_run.update!(attributes)
        sync_run
      end

      Sync::BulkSyncJob.perform_later(sync_run.id) if sync_run.total_count.positive?
      sync_run
    end

    private

      attr_reader :scope, :plan_items_by_assignment_id
  end
end
