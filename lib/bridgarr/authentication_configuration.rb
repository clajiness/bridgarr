require "ipaddr"

module Bridgarr
  module AuthenticationConfiguration
    class ConfigurationError < StandardError; end

    # ActionDispatch falls back to its broad default proxy set for an empty
    # collection. These unroutable/unspecified host addresses make the explicit
    # default effectively "trust no forwarding proxy."
    NO_TRUSTED_PROXIES = [
      IPAddr.new("0.0.0.0/32"),
      IPAddr.new("::/128")
    ].freeze
    CANONICAL_POSITIVE_INTEGER = /\A[1-9][0-9]*\z/

    module_function

    def session_timeout_minutes(value = ENV.fetch("AUTH_SESSION_TIMEOUT_MINUTES", "30"))
      return value.to_i if value.is_a?(String) && value.match?(CANONICAL_POSITIVE_INTEGER)

      raise ConfigurationError, "AUTH_SESSION_TIMEOUT_MINUTES must be a positive integer; received #{value.inspect}"
    end

    def trusted_proxies(value = ENV.fetch("TRUSTED_PROXY_CIDRS", ""))
      proxies = value
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
        .map { |cidr| IPAddr.new(cidr) }
      proxies.presence || NO_TRUSTED_PROXIES
    rescue IPAddr::InvalidAddressError
      raise ConfigurationError, "TRUSTED_PROXY_CIDRS must be a comma-separated list of valid IP addresses or CIDR ranges"
    end
  end
end
