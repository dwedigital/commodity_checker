# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Admin user for development. There is no password to set: sign in with Google
# using this address and the existing record is matched on email.
if Rails.env.development?
  admin = User.find_or_initialize_by(email: "dave@dwedigital.com")
  admin.admin = true
  admin.save!
  puts "Admin user ready: #{admin.email} — sign in with Google using this address"
end
