module Sync
  class PlanApplier
    Result = Data.define(:success?, :sync_run, :message, :error, :stale_assignment_ids)

    def self.call(plan:, assignment_ids:, expected_digests: {}, destructive_confirmation: false)
      new(plan:, assignment_ids:, expected_digests:, destructive_confirmation:).call
    end

    def initialize(plan:, assignment_ids:, expected_digests:, destructive_confirmation:)
      @plan = plan
      @assignment_ids = Array(assignment_ids).map(&:to_i).uniq
      @expected_digests = expected_digests.to_h.stringify_keys
      @destructive_confirmation = destructive_confirmation
    end

    def call
      selected_items = plan.items.select { |item| assignment_ids.include?(item.indexer_app.id) }
      planned_assignment_ids = selected_items.map { |item| item.indexer_app.id }
      stale_ids = assignment_ids - planned_assignment_ids
      stale_ids.concat(selected_items.filter_map do |item|
        expected = expected_digests[item.indexer_app.id.to_s].to_s
        item.indexer_app.id if expected.blank? || !ActiveSupport::SecurityUtils.secure_compare(expected, item.plan_digest)
      end)
      return stale_failure(stale_ids) if stale_ids.any?

      applyable_items = selected_items.select(&:applyable?)
      return failure("No selected reconciliation changes are safe to apply.") if applyable_items.empty?
      if applyable_items.any?(&:destructive) && !destructive_confirmation
        return failure("Confirm that the selected plan will disable remote search modes before applying it.")
      end

      sync_run = BulkSync.call(
        scope: IndexerApp.where(id: applyable_items.map { |item| item.indexer_app.id }),
        plan_items: applyable_items
      )
      if sync_run.status == "failed"
        return Result.new(
          success?: false,
          sync_run:,
          message: sync_run.error,
          error: sync_run.error,
          stale_assignment_ids: []
        )
      end
      message = if sync_run.total_count.positive?
        "Queued #{sync_run.total_count} reconciliation #{'change'.pluralize(sync_run.total_count)}."
      else
        "No new reconciliation work was queued; the selected assignments are already syncing."
      end

      Result.new(
        success?: true,
        sync_run:,
        message:,
        error: nil,
        stale_assignment_ids: []
      )
    end

    private

      attr_reader :plan, :assignment_ids, :expected_digests, :destructive_confirmation

      def stale_failure(stale_ids)
        Result.new(
          success?: false,
          sync_run: nil,
          message: "The reconciliation preview changed. Review the refreshed plan before applying it.",
          error: "The reconciliation preview changed. Review the refreshed plan before applying it.",
          stale_assignment_ids: stale_ids
        )
      end

      def failure(message)
        Result.new(success?: false, sync_run: nil, message:, error: message, stale_assignment_ids: [])
      end
  end
end
