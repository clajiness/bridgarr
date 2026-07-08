Rails.application.config.after_initialize do
  Bridgarr::BuildInfo.log_startup!
end
