module Sync
  class PlanRecorder
    def self.call(plan, inspected_at: plan.generated_at)
      plan.items.each do |item|
        IndexerApp.where(id: item.indexer_app.id).update_all(
          last_plan_state: item.state,
          last_inspected_at: inspected_at,
          last_desired_digest: item.desired_digest,
          last_remote_digest: item.remote_digest
        )
      end

      plan
    end
  end
end
