# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create admin user for development
if Rails.env.development?
  admin = User.find_or_initialize_by(email: "dave@dwedigital.com")
  admin.password = "T0p$ecret!"
  admin.password_confirmation = "T0p$ecret!"
  admin.confirmed_at = Time.current
  admin.admin = true
  admin.save!
  puts "Admin user created: #{admin.email}"
end
