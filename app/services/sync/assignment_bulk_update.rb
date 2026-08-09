module Sync
  class AssignmentBulkUpdate
    ACTIONS = %w[create direct bridged categories search_modes].freeze
    SEARCH_MODE_VALUES = %w[keep enable disable].freeze
    Result = Data.define(:success?, :changed_count, :message, :error)

    def self.call(
      cells:,
      action:,
      category_mode: nil,
      custom_categories: nil,
      enable_rss: nil,
      enable_automatic_search: nil,
      enable_interactive_search: nil
    )
      new(
        cells:,
        action:,
        category_mode:,
        custom_categories:,
        enable_rss:,
        enable_automatic_search:,
        enable_interactive_search:
      ).call
    end

    def initialize(
      cells:,
      action:,
      category_mode:,
      custom_categories:,
      enable_rss:,
      enable_automatic_search:,
      enable_interactive_search:
    )
      @cells = cells
      @action = action.to_s
      @category_mode = category_mode
      @custom_categories = custom_categories
      @search_mode_values = {
        enable_rss: enable_rss.to_s.presence || "keep",
        enable_automatic_search: enable_automatic_search.to_s.presence || "keep",
        enable_interactive_search: enable_interactive_search.to_s.presence || "keep"
      }
    end

    def call
      return failure("Choose a valid bulk action.") unless action.in?(ACTIONS)
      return failure("Choose valid search-mode values.") if action == "search_modes" && search_mode_values.values.any? { |value| !value.in?(SEARCH_MODE_VALUES) }
      return failure("Choose at least one search mode to enable or disable.") if action == "search_modes" && search_mode_values.values.all?("keep")

      changed_count = 0
      IndexerApp.transaction do
        cells.each do |indexer_id, arr_app_id|
          assignment = IndexerApp.find_by(indexer_id:, arr_app_id:)
          if action == "create"
            next if assignment

            assignment = IndexerApp.new(indexer_id:, arr_app_id:)
          else
            next unless assignment
          end

          if assignment.persisted?
            assignment.with_lock { assignment.update!(attributes) }
          else
            assignment.update!(attributes)
          end
          changed_count += 1
        end
      end

      if changed_count.zero? && action != "create"
        return failure("The selected cells do not have assignments yet. Create them before updating their settings.")
      end

      Result.new(
        success?: true,
        changed_count:,
        message: success_message(changed_count),
        error: nil
      )
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::StaleObjectError
      failure("The assignment matrix changed while the bulk update was running. Refresh and try again.")
    end

    private

      attr_reader :cells, :action, :category_mode, :custom_categories, :search_mode_values

      def attributes
        case action
        when "create" then {}
        when "direct", "bridged" then { connection_mode: action }
        when "categories"
          {
            category_mode: category_mode.presence || "auto",
            custom_categories:
          }
        when "search_modes"
          search_mode_values.each_with_object({}) do |(setting, value), selected|
            selected[setting] = value == "enable" unless value == "keep"
          end
        end
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        Result.new(success?: false, changed_count: 0, message:, error: message)
      end

      def success_message(changed_count)
        if action == "create"
          return "No assignments were created because every selected cell is already assigned." if changed_count.zero?

          "Created #{changed_count} #{'assignment'.pluralize(changed_count)}."
        else
          "Updated #{changed_count} #{'assignment'.pluralize(changed_count)}."
        end
      end
  end
end
