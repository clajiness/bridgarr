module AuthenticationRateLimited
  extend ActiveSupport::Concern

  SOURCE_IP_LIMIT = 20
  ACCOUNT_LIMIT = 10
  WINDOW = 5.minutes

  included do
    rate_limit to: SOURCE_IP_LIMIT,
      within: WINDOW,
      by: :authentication_source_ip,
      name: "source-ip",
      only: :create,
      with: :authentication_rate_limit_exceeded
    rate_limit to: ACCOUNT_LIMIT,
      within: WINDOW,
      by: :normalized_authentication_identifier,
      name: "account",
      only: :create,
      with: :authentication_rate_limit_exceeded
  end

  private

    def normalized_authentication_identifier
      params.dig(resource_name, :email).to_s.strip.downcase.presence || "(blank)"
    end

    def authentication_source_ip
      peer_ip = request.remote_addr.to_s
      trusted_proxies = Rails.application.config.action_dispatch.trusted_proxies
      return request.remote_ip if trusted_proxies.any? { |proxy| proxy.include?(peer_ip) }

      peer_ip.presence || "(unknown)"
    rescue IPAddr::InvalidAddressError
      peer_ip.presence || "(unknown)"
    end
end
