# Configure Mission Control Jobs dashboard
# Authentication is handled by Devise in routes.rb (admin? check)
# so we disable the built-in HTTP Basic auth
Rails.application.configure do
  config.mission_control.jobs.http_basic_auth_enabled = false
end
