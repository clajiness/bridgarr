require Rails.root.join("lib/bridgarr/authentication_configuration")

# Trust no forwarding proxy by default. When explicitly configured, Rails uses
# these addresses to derive request.remote_ip safely from forwarding headers.
Rails.application.config.action_dispatch.trusted_proxies =
  Bridgarr::AuthenticationConfiguration.trusted_proxies
