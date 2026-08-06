module Sync
  class AssignmentBulkUpdate
    ACTIONS = %w[create enable disable direct bridged categories].freeze
    Result = Data.define(:success?, :changed_count, :message, :error)

    def self.call(cells:, action:, category_mode: nil, custom_categories: nil)
      new(cells:, action:, category_mode:, custom_categories:).call
    end

    def initialize(cells:, action:, category_mode:, custom_categories:)
      @cells = cells
      @action = action.to_s
      @category_mode = category_mode
      @custom_categories = custom_categories
    end

    def call
      return failure("Choose a valid bulk action.") unless action.in?(ACTIONS)

      changed_count = 0
      IndexerApp.transaction do
        cells.each do |indexer_id, arr_app_id|
          assignment = IndexerApp.find_by(indexer_id:, arr_app_id:)
          next unless action == "create" || assignment

          assignment ||= IndexerApp.new(indexer_id:, arr_app_id:)
          assignment.update!(attributes)
          changed_count += 1
        end
      end

      Result.new(
        success?: true,
        changed_count:,
        message: "Updated #{changed_count} matrix #{'cell'.pluralize(changed_count)}.",
        error: nil
      )
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::StaleObjectError
      failure("The assignment matrix changed while the bulk update was running. Refresh and try again.")
    end

    private

      attr_reader :cells, :action, :category_mode, :custom_categories

      def attributes
        case action
        when "create", "enable" then { enabled: true }
        when "disable" then { enabled: false }
        when "direct", "bridged" then { connection_mode: action }
        when "categories"
          {
            category_mode: category_mode.presence || "auto",
            custom_categories:
          }
        end
      end

      def failure(message)
        message = Secrets::Redactor.call(message)
        Result.new(success?: false, changed_count: 0, message:, error: message)
      end
  end
end
