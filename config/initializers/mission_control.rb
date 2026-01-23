# Configure Mission Control Jobs dashboard
# Authentication is handled by Devise in routes.rb (admin? check)
# so we disable the built-in HTTP Basic auth
MissionControl::Jobs.http_basic_auth_enabled = false
