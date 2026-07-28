require Rails.root.join("lib/bridgarr/health_check_configuration")

Rails.application.config.x.jackett_indexer_health_timeout_seconds =
  Bridgarr::HealthCheckConfiguration.jackett_indexer_timeout_seconds
