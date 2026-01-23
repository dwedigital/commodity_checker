# frozen_string_literal: true

namespace :analytics do
  desc "Seed mock analytics data for development/testing (90 days)"
  task seed: :environment do
    puts "Seeding analytics data for the last 90 days..."

    # Configuration
    days_back = 90
    base_daily_visitors = 5
    growth_rate = 1.02 # 2% daily growth

    devices = %w[Desktop Mobile Tablet]
    device_weights = [ 0.6, 0.35, 0.05 ]

    browsers = [ "Chrome", "Safari", "Firefox", "Edge" ]
    browser_weights = [ 0.65, 0.2, 0.1, 0.05 ]

    referrers = [ nil, "google.com", "twitter.com", "reddit.com", "linkedin.com", "facebook.com" ]
    referrer_weights = [ 0.5, 0.25, 0.08, 0.07, 0.05, 0.05 ]

    landing_pages = [ "/", "/blog", "/users/sign_up", "/users/sign_in", "/pricing" ]
    landing_weights = [ 0.5, 0.2, 0.15, 0.1, 0.05 ]

    # Get existing users for authenticated events
    users = User.all.to_a

    total_visits = 0
    total_events = 0

    days_back.downto(1) do |days_ago|
      date = days_ago.days.ago.to_date

      # More visitors on weekdays
      weekday_multiplier = date.on_weekday? ? 1.0 : 0.6

      # Growth over time (more recent = more visitors)
      time_multiplier = growth_rate ** (days_back - days_ago)

      # Random daily variation
      random_variation = rand(0.7..1.3)

      daily_visitors = (base_daily_visitors * weekday_multiplier * time_multiplier * random_variation).round
      daily_visitors = [ daily_visitors, 1 ].max

      daily_visitors.times do
        # Create a visit
        started_at = date.to_time + rand(8..22).hours + rand(60).minutes

        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.uuid,
          visitor_token: SecureRandom.uuid,
          user_id: rand < 0.3 ? users.sample&.id : nil, # 30% are logged in
          started_at: started_at,
          device_type: weighted_sample(devices, device_weights),
          browser: weighted_sample(browsers, browser_weights),
          referring_domain: weighted_sample(referrers, referrer_weights),
          landing_page: weighted_sample(landing_pages, landing_weights),
          ip: "192.168.1.#{rand(1..254)}"
        )
        total_visits += 1

        # Page views (1-5 per visit)
        rand(1..5).times do
          Ahoy::Event.create!(
            visit_id: visit.id,
            user_id: visit.user_id,
            name: "page_view",
            properties: { page: landing_pages.sample },
            time: started_at + rand(1..30).minutes
          )
          total_events += 1
        end

        # Lookups (40% of visits result in a lookup)
        if rand < 0.4
          lookup_time = started_at + rand(2..15).minutes

          if visit.user_id
            # Authenticated lookup
            lookup_type = rand < 0.15 ? "photo" : "url"
            Ahoy::Event.create!(
              visit_id: visit.id,
              user_id: visit.user_id,
              name: "user_lookup_performed",
              properties: {
                lookup_type: lookup_type,
                lookup_id: rand(1000..9999)
              },
              time: lookup_time
            )
          else
            # Guest lookup
            Ahoy::Event.create!(
              visit_id: visit.id,
              user_id: nil,
              name: "guest_lookup_performed",
              properties: {
                lookup_type: "url",
                guest_token: SecureRandom.hex(8)
              },
              time: lookup_time
            )

            # 10% hit the guest limit
            if rand < 0.1
              Ahoy::Event.create!(
                visit_id: visit.id,
                user_id: nil,
                name: "guest_limit_reached",
                properties: { guest_token: SecureRandom.hex(8) },
                time: lookup_time + 1.minute
              )
              total_events += 1
            end
          end
          total_events += 1
        end

        # Extension lookups (10% of visits)
        if rand < 0.1
          Ahoy::Event.create!(
            visit_id: visit.id,
            user_id: visit.user_id,
            name: "extension_lookup_performed",
            properties: {
              lookup_type: "url",
              source: "extension",
              authenticated: visit.user_id.present?,
              extension_id: "ext_#{SecureRandom.hex(8)}"
            },
            time: started_at + rand(5..20).minutes
          )
          total_events += 1
        end
      end

      # Signups (1-3 per day with growth)
      signup_count = (rand(0..2) * time_multiplier * weekday_multiplier).round
      signup_count.times do
        signup_time = date.to_time + rand(8..22).hours + rand(60).minutes
        Ahoy::Event.create!(
          visit_id: nil,
          user_id: users.sample&.id,
          name: "user_registered",
          properties: { registration_source: "direct" },
          time: signup_time
        )
        total_events += 1
      end

      # Email-based orders (0-2 per day)
      rand(0..2).times do
        order_time = date.to_time + rand(8..22).hours + rand(60).minutes
        Ahoy::Event.create!(
          visit_id: nil,
          user_id: users.sample&.id,
          name: "order_created",
          properties: { source: "email", retailer: [ "Amazon", "ASOS", "eBay" ].sample },
          time: order_time
        )
        total_events += 1
      end

      print "." if days_ago % 10 == 0
    end

    puts "\nDone! Created #{total_visits} visits and #{total_events} events."
  end

  desc "Clear all analytics data (visits and events)"
  task clear: :environment do
    puts "Clearing all analytics data..."
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    puts "Done!"
  end
end

def weighted_sample(items, weights)
  total = weights.sum
  r = rand * total
  cumulative = 0

  items.each_with_index do |item, i|
    cumulative += weights[i]
    return item if r <= cumulative
  end

  items.last
end
