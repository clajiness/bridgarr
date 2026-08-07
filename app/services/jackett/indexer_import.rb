module Jackett
  class IndexerImport
    Result = Struct.new(
      :success?,
      :imported_count,
      :updated_count,
      :assigned_count,
      :skipped_count,
      :sync_run,
      :preview_assignment_ids,
      :message,
      :error,
      keyword_init: true
    )

    def self.call(
      base_url:,
      api_key:,
      jackett_ids: [],
      arr_app_ids: [],
      connection_mode: "direct",
      category_mode: "auto",
      custom_categories: nil,
      sync_now: false,
      discovery: IndexerDiscovery
    )
      new(
        base_url:,
        api_key:,
        jackett_ids:,
        arr_app_ids:,
        connection_mode:,
        category_mode:,
        custom_categories:,
        sync_now:,
        discovery:
      ).call
    end

    def initialize(base_url:, api_key:, jackett_ids:, arr_app_ids:, connection_mode:, category_mode:, custom_categories:, sync_now:, discovery:)
      @base_url = base_url
      @api_key = api_key
      @jackett_ids = Array(jackett_ids).map(&:to_s).reject(&:blank?).uniq
      requested_arr_app_ids = Array(arr_app_ids).map(&:to_s).reject(&:blank?).uniq
      @arr_app_ids = requested_arr_app_ids.filter_map { |value| positive_integer(value) }.uniq
      @invalid_destination_selection = requested_arr_app_ids.size != @arr_app_ids.size
      @assignment_attributes = {
        connection_mode: connection_mode.presence || "direct",
        category_mode: category_mode.presence || "auto",
        custom_categories:
      }
      @sync_now = ActiveModel::Type::Boolean.new.cast(sync_now)
      @discovery = discovery
    end

    def call
      return failure("Choose at least one Jackett indexer to import.") if jackett_ids.empty?

      discovery_result = discovery.call(base_url:, api_key:)
      return failure(discovery_result.message) unless discovery_result.success?

      selected_records = discovery_result.indexers.select { |record| jackett_ids.include?(record.jackett_id) && record.configured }
      unavailable_jackett_ids = jackett_ids - selected_records.map(&:jackett_id)
      if unavailable_jackett_ids.any?
        return failure("The selected Jackett inventory changed. Rediscover indexers and review #{unavailable_jackett_ids.to_sentence}.")
      end

      destination_error = validate_destinations
      return failure(destination_error) if destination_error

      imported_count = 0
      updated_count = 0
      assigned_count = 0
      skipped_count = 0
      assignments = []

      Indexer.transaction do
        selected_records.each do |jackett_indexer|
          indexer = Indexer.find_or_initialize_by(jackett_id: jackett_indexer.jackett_id)

          if indexer.persisted?
            changed = indexer.name != jackett_indexer.name ||
              indexer.jackett_source_digest.present? && indexer.jackett_source_digest != jackett_indexer.source_digest ||
              indexer.jackett_state.in?(%w[renamed changed disabled missing])
            indexer.name = jackett_indexer.name
            changed ? updated_count += 1 : skipped_count += 1
          else
            indexer.name = jackett_indexer.name
            indexer.enabled = true
            imported_count += 1
          end

          indexer.assign_attributes(
            jackett_name: jackett_indexer.name,
            jackett_configured: true,
            jackett_last_seen_at: Time.current,
            jackett_missing_since: nil,
            jackett_source_digest: jackett_indexer.source_digest,
            jackett_state: "unchanged"
          )
          indexer.save!

          arr_app_ids.each do |arr_app_id|
            assignment = IndexerApp.find_or_initialize_by(indexer:, arr_app_id:)
            new_assignment = assignment.new_record?
            assigned_count += 1 if new_assignment
            attributes = new_assignment ? assignment_attributes.merge(enabled: true) : assignment_attributes
            assignment.update!(attributes)
            assignments << assignment
          end
        end
      end

      assignment_ids = assignments.map(&:id).uniq
      preview_assignment_ids = if sync_now && assignments.any? { |assignment| !assignment.enabled? }
        assignment_ids
      else
        []
      end
      sync_run = Sync::BulkSync.call(scope: IndexerApp.where(id: assignment_ids)) if sync_now && assignment_ids.any? && preview_assignment_ids.empty?
      success(imported_count:, updated_count:, assigned_count:, skipped_count:, sync_run:, preview_assignment_ids:)
    rescue ActiveRecord::RecordInvalid => e
      failure("Could not import Jackett indexers: #{e.record.errors.full_messages.to_sentence}")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey
      failure("The Jackett inventory or destination selection changed while importing. Rediscover and try again.")
    end

    private

      attr_reader :base_url,
        :api_key,
        :jackett_ids,
        :arr_app_ids,
        :assignment_attributes,
        :sync_now,
        :discovery,
        :invalid_destination_selection

      def success(imported_count:, updated_count:, assigned_count:, skipped_count:, sync_run:, preview_assignment_ids:)
        Result.new(
          success?: true,
          imported_count:,
          updated_count:,
          assigned_count:,
          skipped_count:,
          sync_run:,
          preview_assignment_ids:,
          message: import_message(imported_count:, updated_count:, assigned_count:, skipped_count:, sync_run:, preview_assignment_ids:),
          error: nil
        )
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        Result.new(
          success?: false,
          imported_count: 0,
          updated_count: 0,
          assigned_count: 0,
          skipped_count: 0,
          sync_run: nil,
          preview_assignment_ids: [],
          message:,
          error: message
        )
      end

      def import_message(imported_count:, updated_count:, assigned_count:, skipped_count:, sync_run:, preview_assignment_ids:)
        parts = [
          "#{imported_count} #{'indexer'.pluralize(imported_count)} imported",
          "#{updated_count} updated",
          "#{assigned_count} #{'assignment'.pluralize(assigned_count)} created",
          "#{skipped_count} unchanged"
        ]
        if preview_assignment_ids.any?
          parts << "preview required before syncing disabled desired state"
        elsif sync_run
          parts << (sync_run.total_count.positive? ? "sync queued" : "sync already active")
        end
        "#{parts.join(', ')}."
      end

      def validate_destinations
        return "The selected destination inventory changed. Review the enabled applications and try again." if invalid_destination_selection
        return if arr_app_ids.empty?

        available_ids = ArrApp.where(id: arr_app_ids, enabled: true).pluck(:id)
        unavailable_ids = arr_app_ids - available_ids
        return if unavailable_ids.empty?

        "The selected destination inventory changed. Review the enabled applications and try again."
      end

      def positive_integer(value)
        parsed = Integer(value.to_s, 10, exception: false)
        parsed if parsed&.positive?
      end
  end
end
