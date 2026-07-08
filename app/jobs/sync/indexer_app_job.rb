module Sync
  class IndexerAppJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    RETRY_DELAY = ENV.fetch("BRIDGARR_SYNC_RETRY_DELAY_SECONDS", "45").to_i.seconds
    CONCURRENCY_DURATION = ENV.fetch("BRIDGARR_INDEXER_SYNC_CONCURRENCY_SECONDS", "600").to_i.seconds

    limits_concurrency(
      key: ->(sync_run_item_id) { self.class.indexer_concurrency_key(sync_run_item_id) },
      to: 1,
      group: "sync:indexer",
      duration: CONCURRENCY_DURATION
    )

    def self.indexer_concurrency_key(sync_run_item_id)
      sync_run_item = SyncRunItem.includes(:indexer_app).find_by(id: sync_run_item_id)
      indexer_id = sync_run_item&.indexer_app&.indexer_id

      indexer_id.present? ? "indexer:#{indexer_id}" : "sync_run_item:#{sync_run_item_id}"
    end

    def perform(sync_run_item_id)
      sync_run_item = SyncRunItem.includes(indexer_app: %i[indexer arr_app]).find(sync_run_item_id)
      return if sync_run_item.terminal?

      sync_run = sync_run_item.sync_run

      sync_run.mark_running!
      return record_missing_assignment(sync_run_item) if sync_run_item.indexer_app.blank?

      sync_run_item.mark_running!
      log_sync_event(
        "Starting indexer app sync",
        sync_run_item:,
        attempt: sync_run_item.attempt_count,
        concurrency_key: self.class.indexer_concurrency_key(sync_run_item.id)
      )

      live_sync_started_at = monotonic_time
      result = Sync::IndexerAppSync.call(indexer_app: sync_run_item.indexer_app)
      record_result(sync_run_item, result)
      log_sync_event(
        "Finished indexer app sync",
        sync_run_item:,
        attempt: sync_run_item.attempt_count,
        result: sync_run_item.reload.status,
        live_sync_duration_ms: elapsed_ms(live_sync_started_at)
      )
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Sync::IndexerAppJob could not find SyncRunItem #{sync_run_item_id}. It may have been removed before the job ran.")
      raise
    rescue StandardError => e
      record_exception(sync_run_item, e)
    ensure
      sync_run_item&.sync_run&.refresh_status!
    end

    private

      def record_missing_assignment(sync_run_item)
        message = "Assignment was removed before sync."
        classification = Sync::ErrorClassifier.call(message)

        sync_run_item.update!(
          status: "failed",
          finished_at: Time.current,
          error: message,
          error_kind: classification.kind,
          retryable: classification.retryable?,
          next_retry_at: nil
        )
      end

      def record_result(sync_run_item, result)
        error = result.error.presence || result.message
        sanitized_error = result.success? ? nil : Secrets::Redactor.call(error)
        classification = sanitized_error.present? ? Sync::ErrorClassifier.call(sanitized_error, skipped: result.skipped?) : nil

        if should_retry?(sync_run_item, classification)
          schedule_retry(sync_run_item, error: sanitized_error, classification:)
        else
          sync_run_item.record_result!(result)
        end
      end

      def record_exception(sync_run_item, exception)
        return unless sync_run_item

        error = Secrets::Redactor.call(exception.message)
        classification = Sync::ErrorClassifier.call(error)

        if should_retry?(sync_run_item, classification)
          schedule_retry(sync_run_item, error:, classification:)
        else
          sync_run_item.update!(
            status: "failed",
            finished_at: Time.current,
            error:,
            error_kind: classification.kind,
            retryable: classification.retryable?,
            next_retry_at: nil
          )
        end
      end

      def should_retry?(sync_run_item, classification)
        classification&.retryable? && sync_run_item.attempt_count < sync_run_item.max_attempts
      end

      def schedule_retry(sync_run_item, error:, classification:)
        retry_at = Time.current + RETRY_DELAY

        sync_run_item.record_retry!(
          error:,
          classification:,
          next_retry_at: retry_at
        )

        log_sync_event(
          "Scheduled sync retry",
          sync_run_item:,
          attempt: sync_run_item.attempt_count,
          next_attempt: sync_run_item.attempt_count + 1,
          delay_seconds: RETRY_DELAY.to_i,
          error_kind: classification.kind
        )

        self.class.set(wait_until: retry_at).perform_later(sync_run_item.id)
      end

      def log_sync_event(message, sync_run_item:, **attributes)
        indexer_app = sync_run_item.indexer_app
        Rails.logger.info(
          {
            message:,
            sync_run_id: sync_run_item.sync_run_id,
            sync_run_item_id: sync_run_item.id,
            indexer_app_id: indexer_app&.id,
            indexer_id: indexer_app&.indexer_id,
            jackett_id: indexer_app&.indexer&.jackett_id
          }.merge(attributes)
        )
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1000).round
      end
  end
end
