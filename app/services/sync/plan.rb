require "digest"

module Sync
  class Plan
    STATES = %w[create update unchanged not_applicable conflict orphaned unreachable invalid].freeze
    APPLYABLE_STATES = %w[create update unchanged].freeze

    Result = Data.define(:items, :generated_at) do
      def counts
        items.group_by(&:state).transform_values(&:count)
      end

      def applyable_items
        items.select(&:applyable?)
      end

      def attention_items
        items.select(&:attention?)
      end

      def destructive_items
        items.select(&:destructive)
      end
    end

    Item = Data.define(
      :indexer_app,
      :state,
      :remote_indexer_id,
      :changes,
      :message,
      :desired_digest,
      :remote_digest,
      :plan_digest,
      :destructive
    ) do
      def applyable?
        APPLYABLE_STATES.include?(state)
      end

      def changed?
        changes.any?
      end

      def attention?
        !applyable? && state != "not_applicable"
      end
    end

    FIELD_LABELS = {
      "name" => "Name",
      "enableRss" => "RSS",
      "enableAutomaticSearch" => "Automatic search",
      "enableInteractiveSearch" => "Interactive search",
      "baseUrl" => "Torznab URL",
      "apiPath" => "API path",
      "apiKey" => "API key",
      "categories" => "Categories",
      "animeCategories" => "Anime categories"
    }.freeze
    SEARCH_MODE_FIELDS = %w[enableRss enableAutomaticSearch enableInteractiveSearch].freeze
    REQUIRED_TORZNAB_FIELDS = %w[baseUrl apiPath apiKey].freeze
    PRIVATE_FIELD_VALUE = "********"

    def self.call(scope: IndexerApp.all, inventory_client: Arr::IndexerInventory, caps_client: Jackett::TorznabCaps, now: Time.current)
      new(scope:, inventory_client:, caps_client:, now:).call
    end

    def initialize(scope:, inventory_client:, caps_client:, now:)
      @assignments = scope.includes(:indexer, :arr_app).to_a
      @inventory_client = inventory_client
      @caps_client = caps_client
      @now = now
      @caps_cache = {}
    end

    def call
      items = assignments.group_by(&:arr_app).flat_map do |arr_app, app_assignments|
        plan_app(arr_app, app_assignments)
      end

      Result.new(items:, generated_at: now)
    end

    private

      attr_reader :assignments, :inventory_client, :caps_client, :caps_cache, :now

      def plan_app(arr_app, app_assignments)
        unless arr_app.enabled?
          return app_assignments.map { |assignment| invalid_item(assignment, "Enable #{arr_app.name} before reconciling assignments.") }
        end

        inventory = inventory_client.call(arr_app:)
        unless inventory.success?
          return app_assignments.map { |assignment| unreachable_item(assignment, inventory.message) }
        end

        app_assignments.map { |assignment| plan_assignment(assignment, inventory) }
      end

      def plan_assignment(assignment, inventory)
        desired_result = DesiredConfiguration.call(
          indexer_app: assignment,
          torznab_schema: inventory.torznab_schema,
          caps_client:,
          caps_cache:
        )
        unless desired_result.success?
          return not_applicable_item(assignment, desired_result.message) if desired_result.not_applicable?

          return invalid_item(assignment, desired_result.message)
        end

        desired = desired_result.configuration
        remote_by_id = find_by_id(inventory.indexers, assignment.remote_indexer_id)
        overlap = find_overlap(inventory.indexers, desired.attributes)

        if assignment.remote_indexer_id.present? && remote_by_id.nil?
          return conflict_item(assignment, overlap, desired) if overlap

          return orphaned_item(assignment, desired)
        end

        if remote_by_id.nil? && overlap
          return conflict_item(assignment, overlap, desired)
        end

        return create_item(assignment, desired) unless remote_by_id
        return invalid_item(assignment, "#{arr_app_name(assignment)} did not return configurable fields for the managed indexer.", desired:) unless configurable?(remote_by_id)

        comparison_item(assignment, remote_by_id, desired)
      end

      def comparison_item(assignment, remote, desired)
        remote_attributes = normalized_remote_attributes(remote)
        comparable_remote_attributes = comparable_remote_attributes(assignment, remote_attributes, desired.attributes)
        changes = changes_between(comparable_remote_attributes, desired.attributes)
        state = changes.empty? ? "unchanged" : "update"
        remote_digest = DesiredConfiguration.digest(comparable_remote_attributes)
        destructive = disables_remote_search?(remote_attributes, desired.attributes)
        message = state == "unchanged" ? "Remote configuration already matches." : update_message(assignment, desired.digest, remote_digest, changes.size)
        message = "#{message} Remote RSS, automatic search, and interactive search will be disabled." if destructive

        build_item(
          assignment:,
          state:,
          remote_indexer_id: remote["id"],
          changes:,
          message:,
          desired_digest: desired.digest,
          remote_digest:,
          destructive:
        )
      end

      def create_item(assignment, desired)
        destructive = SEARCH_MODE_FIELDS.any? { |field| desired.attributes[field] == false }
        message = if destructive
          "A managed Generic Torznab indexer will be created with remote RSS, automatic search, and interactive search disabled."
        else
          "A managed Generic Torznab indexer will be created."
        end

        build_item(
          assignment:,
          state: "create",
          remote_indexer_id: nil,
          changes: [],
          message:,
          desired_digest: desired.digest,
          remote_digest: nil,
          destructive:
        )
      end

      def update_message(assignment, desired_digest, remote_digest, change_count)
        base = "#{change_count} #{'field'.pluralize(change_count)} will change."
        return base if assignment.last_applied_digest.blank?

        local_changed = assignment.last_applied_digest != desired_digest
        remote_changed = assignment.last_applied_digest != remote_digest

        if local_changed && remote_changed
          "Local desired state and remote configuration both changed. #{base}"
        elsif local_changed
          "Local desired state changed since the last successful apply. #{base}"
        elsif remote_changed
          "Remote drift was detected. #{base}"
        else
          base
        end
      end

      def conflict_item(assignment, remote, desired)
        build_item(
          assignment:,
          state: "conflict",
          remote_indexer_id: remote["id"],
          changes: [],
          message: "A potentially overlapping unmanaged indexer already exists as remote ID #{remote['id']}. Repair or resolve it before applying.",
          desired_digest: desired.digest,
          remote_digest: configurable?(remote) ? DesiredConfiguration.digest(normalized_remote_attributes(remote)) : nil,
          destructive: false
        )
      end

      def orphaned_item(assignment, desired)
        build_item(
          assignment:,
          state: "orphaned",
          remote_indexer_id: assignment.remote_indexer_id,
          changes: [],
          message: "Remote indexer ID #{assignment.remote_indexer_id} no longer exists. Repair or forget the stale association.",
          desired_digest: desired.digest,
          remote_digest: nil,
          destructive: false
        )
      end

      def unreachable_item(assignment, message)
        build_item(
          assignment:,
          state: "unreachable",
          remote_indexer_id: assignment.remote_indexer_id,
          changes: [],
          message:,
          desired_digest: nil,
          remote_digest: nil,
          destructive: false
        )
      end

      def invalid_item(assignment, message, desired: nil)
        build_item(
          assignment:,
          state: "invalid",
          remote_indexer_id: assignment.remote_indexer_id,
          changes: [],
          message:,
          desired_digest: desired&.digest,
          remote_digest: nil,
          destructive: false
        )
      end

      def not_applicable_item(assignment, message)
        build_item(
          assignment:,
          state: "not_applicable",
          remote_indexer_id: assignment.remote_indexer_id,
          changes: [],
          message:,
          desired_digest: nil,
          remote_digest: nil,
          destructive: false
        )
      end

      def build_item(assignment:, state:, remote_indexer_id:, changes:, message:, desired_digest:, remote_digest:, destructive:)
        digest_input = {
          assignment_id: assignment.id,
          assignment_updated_at: assignment.updated_at&.iso8601(6),
          destination_digest: destination_digest(assignment.arr_app),
          state:,
          remote_indexer_id:,
          desired_digest:,
          remote_digest:
        }

        Item.new(
          indexer_app: assignment,
          state:,
          remote_indexer_id:,
          changes:,
          message: Secrets::Redactor.call(message),
          desired_digest:,
          remote_digest:,
          plan_digest: Digest::SHA256.hexdigest(JSON.generate(digest_input)),
          destructive:
        )
      end

      def find_by_id(indexers, remote_indexer_id)
        return if remote_indexer_id.blank?

        indexers.find { |remote| remote["id"].to_s == remote_indexer_id.to_s }
      end

      def find_overlap(indexers, desired_attributes)
        indexers.find do |remote|
          remote["name"] == desired_attributes["name"] || same_endpoint?(remote, desired_attributes)
        end
      end

      def same_endpoint?(remote, desired_attributes)
        fields = remote["fields"]
        return false unless fields.is_a?(Array) && fields.all?(Hash)

        fields_by_name = fields.index_by { |field| field["name"] }
        fields_by_name.dig("baseUrl", "value") == desired_attributes["baseUrl"] &&
          fields_by_name.dig("apiPath", "value").to_s == desired_attributes["apiPath"]
      end

      def configurable?(remote)
        fields = remote["fields"]
        return false unless fields.is_a?(Array) && fields.all? { |field| field.is_a?(Hash) && field["name"].present? }

        field_names = fields.pluck("name")
        REQUIRED_TORZNAB_FIELDS.all? { |field_name| field_names.include?(field_name) }
      end

      def normalized_remote_attributes(remote)
        fields = remote.fetch("fields").index_by { |field| field["name"] }

        {
          "name" => remote["name"],
          "enableRss" => boolean_value(remote["enableRss"]),
          "enableAutomaticSearch" => boolean_value(remote["enableAutomaticSearch"]),
          "enableInteractiveSearch" => boolean_value(remote["enableInteractiveSearch"]),
          "baseUrl" => fields.dig("baseUrl", "value"),
          "apiPath" => fields.dig("apiPath", "value"),
          "apiKey" => fields.dig("apiKey", "value"),
          "categories" => category_values(fields.dig("categories", "value")),
          "animeCategories" => category_values(fields.dig("animeCategories", "value"))
        }
      end

      def comparable_remote_attributes(assignment, remote_attributes, desired_attributes)
        return remote_attributes unless remote_attributes["apiKey"] == PRIVATE_FIELD_VALUE
        return remote_attributes if assignment.api_key_update_required?

        remote_attributes.merge("apiKey" => desired_attributes["apiKey"])
      end

      def boolean_value(value)
        return true if value.nil?

        ActiveModel::Type::Boolean.new.cast(value)
      end

      def category_values(value)
        Array(value).flat_map { |category_id| category_id.to_s.scan(/\d+/) }.map(&:to_i).select(&:positive?).uniq.sort
      end

      def changes_between(current, desired)
        FIELD_LABELS.filter_map do |field, label|
          next if current[field] == desired[field]

          sensitive = field == "apiKey"
          {
            "field" => field,
            "label" => label,
            "current" => sensitive ? "[REDACTED]" : display_value(current[field]),
            "desired" => sensitive ? "[REDACTED]" : display_value(desired[field]),
            "sensitive" => sensitive
          }
        end
      end

      def disables_remote_search?(remote_attributes, desired_attributes)
        SEARCH_MODE_FIELDS.any? do |field|
          remote_attributes[field] != false && desired_attributes[field] == false
        end
      end

      def display_value(value)
        case value
        when Array then value.join(", ").presence || "None"
        when TrueClass then "Enabled"
        when FalseClass then "Disabled"
        else Secrets::Redactor.call(value.to_s.presence || "None")
        end
      end

      def destination_digest(arr_app)
        Digest::SHA256.hexdigest(JSON.generate(base_url: arr_app.base_url, api_key: arr_app.api_key))
      end

      def arr_app_name(assignment)
        assignment.arr_app.name
      end
  end
end
