class Ahoy::Store < Ahoy::DatabaseStore
end

# Enable JavaScript tracking for client-side events
Ahoy.api = true

# Privacy-first: Cookieless mode
Ahoy.cookies = :none

# Don't track bots
Ahoy.track_bots = false

# Mask IP addresses for privacy
Ahoy.mask_ips = true

# Disable geocoding (no external lookups)
Ahoy.geocode = false

# In cookieless mode (:none), Ahoy automatically generates anonymous
# visitor tokens without storing cookies
