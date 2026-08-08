module Sync
  class PlanRecorder
    def self.call(plan, inspected_at: plan.generated_at)
      plan.items.each do |item|
        attributes = {
          last_plan_state: item.state,
          last_inspected_at: inspected_at,
          last_desired_digest: item.desired_digest,
          last_remote_digest: item.remote_digest
        }
        if item.state == "unchanged"
          attributes[:last_applied_digest] = item.desired_digest
          attributes[:last_applied_settings] = item.indexer_app.desired_settings_snapshot
        end

        IndexerApp.where(id: item.indexer_app.id).update_all(attributes)
      end

      broadcast_live_refreshes(plan)
      plan
    end

    def self.broadcast_live_refreshes(plan)
      return if plan.items.empty?

      %w[dashboard readiness assignment_matrix indexers arr_apps].each do |stream|
        Turbo::StreamsChannel.broadcast_refresh_later_to stream
      end
    end
    private_class_method :broadcast_live_refreshes
  end
end
