require_relative "sensitive_log_silencer"

module Bridgarr
  module SecretPersistence
    module_function

    def without_sql_logging
      Bridgarr::SensitiveLogSilencer.call(ActiveRecord::Base.logger) { yield }
    end
  end
end
