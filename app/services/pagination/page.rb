module Pagination
  class Page
    DEFAULT_PAGE_SIZE = 25
    PAGE_SIZE_OPTIONS = [ 10, 25, 50, 100 ].freeze

    attr_reader :current_page, :per_page, :total_count, :total_pages, :records

    def initialize(collection:, page: 1, per_page: DEFAULT_PAGE_SIZE, default_page_size: DEFAULT_PAGE_SIZE)
      @collection = collection
      @requested_page = positive_integer(page) || 1
      @default_page_size = allowed_default_page_size(default_page_size)
      @per_page = allowed_page_size(per_page)
      @total_count = collection.count
      @total_pages = [ (total_count.to_f / @per_page).ceil, 1 ].max
      @current_page = [ @requested_page, @total_pages ].min
      @records = paginated_records
    end

    def previous_page?
      current_page > 1
    end

    def next_page?
      current_page < total_pages
    end

    def first_item_number
      return 0 if total_count.zero?

      ((current_page - 1) * per_page) + 1
    end

    def last_item_number
      [ current_page * per_page, total_count ].min
    end

    private

      attr_reader :collection, :requested_page, :default_page_size

      def paginated_records
        offset = (current_page - 1) * per_page

        if collection.respond_to?(:offset)
          collection.offset(offset).limit(per_page)
        else
          collection.slice(offset, per_page) || []
        end
      end

      def positive_integer(value)
        integer = Integer(value, exception: false)
        integer if integer&.positive?
      end

      def allowed_default_page_size(value)
        requested_size = positive_integer(value)
        PAGE_SIZE_OPTIONS.include?(requested_size) ? requested_size : DEFAULT_PAGE_SIZE
      end

      def allowed_page_size(value)
        requested_size = positive_integer(value)
        PAGE_SIZE_OPTIONS.include?(requested_size) ? requested_size : default_page_size
      end
  end
end
