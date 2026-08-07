module Sync
  class DesiredStateReverter
    Option = Data.define(:key, :label, :setting_keys, :remote_fields)
    Result = Data.define(:success?, :message, :error, :reverted_assignment_ids)

    OPTIONS = [
      Option.new(
        key: "enabled",
        label: "enabled state",
        setting_keys: %w[enabled],
        remote_fields: %w[enableRss enableAutomaticSearch enableInteractiveSearch]
      ),
      Option.new(
        key: "connection_mode",
        label: "connection mode",
        setting_keys: %w[connection_mode],
        remote_fields: %w[baseUrl apiKey]
      ),
      Option.new(
        key: "categories",
        label: "category settings",
        setting_keys: %w[category_mode custom_categories],
        remote_fields: %w[categories animeCategories]
      )
    ].freeze

    class StaleRevert < StandardError; end

    def self.call(plan:, requests:, expected_digests: {})
      new(plan:, requests:, expected_digests:).call
    end

    def self.options_for(item)
      return [] unless item.state == "update"

      assignment = item.indexer_app
      applied = assignment.last_applied_settings_snapshot
      return [] unless applied

      current = assignment.desired_settings_snapshot
      remote_fields = item.changes.pluck("field")

      OPTIONS.select do |option|
        option.setting_keys.any? { |key| current[key] != applied[key] } &&
          option.remote_fields.any? { |field| remote_fields.include?(field) }
      end
    end

    def initialize(plan:, requests:, expected_digests:)
      @plan = plan
      @requests = normalize_requests(requests)
      @expected_digests = expected_digests.to_h.stringify_keys
    end

    def call
      return failure("Choose at least one local desired-state change to revert.") if requests.empty?

      actions = build_actions
      return actions if actions.is_a?(Result)

      reverted_ids = []
      option_count = actions.sum { |action| action.fetch(:options).size }

      IndexerApp.transaction do
        actions.each do |action|
          item = action.fetch(:item)
          assignment = IndexerApp.lock.find(item.indexer_app.id)
          raise StaleRevert unless assignment.updated_at == item.indexer_app.updated_at

          applied = assignment.last_applied_settings_snapshot
          raise StaleRevert unless applied

          attributes = action.fetch(:options)
            .flat_map(&:setting_keys)
            .uniq
            .to_h { |key| [ key, applied.fetch(key) ] }
          assignment.update!(attributes)
          reverted_ids << assignment.id
        end
      end

      assignment_count = reverted_ids.uniq.size
      Result.new(
        success?: true,
        message: "Reverted #{option_count} local desired-state #{'change'.pluralize(option_count)} across #{assignment_count} #{'assignment'.pluralize(assignment_count)}.",
        error: nil,
        reverted_assignment_ids: reverted_ids.uniq
      )
    rescue StaleRevert, ActiveRecord::RecordNotFound
      failure("The reconciliation preview changed. Review the refreshed plan before reverting local changes.")
    rescue ActiveRecord::RecordInvalid => e
      failure("Could not revert local changes: #{e.record.errors.full_messages.to_sentence}")
    end

    private

      attr_reader :plan, :requests, :expected_digests

      def normalize_requests(raw_requests)
        raw_requests.to_h.each_with_object({}) do |(raw_id, raw_keys), normalized|
          id = Integer(raw_id.to_s, 10, exception: false)
          next unless id&.positive?

          keys = Array(raw_keys).map(&:to_s).uniq
          normalized[id] = keys if keys.any?
        end
      end

      def build_actions
        items_by_id = plan.items.index_by { |item| item.indexer_app.id }

        requests.each_with_object([]) do |(assignment_id, requested_keys), actions|
          item = items_by_id[assignment_id]
          return stale_failure unless item && matching_digest?(item)

          available_options = self.class.options_for(item)
          selected_options = if requested_keys == [ "all" ]
            available_options
          else
            return stale_failure if requested_keys.include?("all")

            available_options.select { |option| requested_keys.include?(option.key) }
          end
          return stale_failure unless selected_options.size == requested_keys.size || requested_keys == [ "all" ]
          return stale_failure if selected_options.empty?

          actions << { item:, options: selected_options }
        end
      end

      def matching_digest?(item)
        expected = expected_digests[item.indexer_app.id.to_s].to_s
        expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, item.plan_digest)
      end

      def stale_failure
        failure("The reconciliation preview changed. Review the refreshed plan before reverting local changes.")
      end

      def failure(message)
        Result.new(success?: false, message:, error: message, reverted_assignment_ids: [])
      end
  end
end
