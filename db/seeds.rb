# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Admin user for development.
#
# The password is generated rather than written down here: a working credential
# committed to the repo is one worth stealing, however local it is meant to be.
# Set SEED_ADMIN_PASSWORD to choose your own, or sign in with Google on the same
# address instead.
if Rails.env.development?
  admin = User.find_or_initialize_by(email: "dave@dwedigital.com")
  password = ENV["SEED_ADMIN_PASSWORD"].presence || "#{SecureRandom.alphanumeric(16)}aA1"

  admin.password = password
  admin.password_confirmation = password
  admin.confirmed_at ||= Time.current
  admin.admin = true
  admin.save!

  puts "Admin user ready: #{admin.email}"
  puts "  password: #{password}"
  puts "  or sign in with Google using the same address"
end
