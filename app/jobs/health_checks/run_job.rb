module HealthChecks
  class RunJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    CONCURRENCY_DURATION = 2.hours

    limits_concurrency(
      key: -> { "full-cycle" },
      to: 1,
      group: "health_checks",
      duration: CONCURRENCY_DURATION
    )

    def perform
      HealthChecks::Runner.call
    end
  end
end
