# frozen_string_literal: true

module Admin
  class AnalyticsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def index
      @period = params[:period] || "30d"
      @start_date = parse_period(@period)

      load_visitor_stats
      load_page_views
      load_lookup_stats
      load_signup_stats
      load_usage_trends
    end

    private

    def require_admin!
      unless current_user.admin?
        redirect_to root_path, alert: "Access denied."
      end
    end

    def parse_period(period)
      case period
      when "7d" then 7.days.ago.beginning_of_day
      when "30d" then 30.days.ago.beginning_of_day
      when "90d" then 90.days.ago.beginning_of_day
      when "1y" then 1.year.ago.beginning_of_day
      else 30.days.ago.beginning_of_day
      end
    end

    def load_visitor_stats
      visits = Ahoy::Visit.where("started_at >= ?", @start_date)

      @total_visitors = visits.distinct.count(:visitor_token)
      @total_visits = visits.count

      # Visitors by day for chart
      @visitors_by_day = visits
        .group("DATE(started_at)")
        .count
        .transform_keys { |k| k.to_date }
        .sort
        .to_h

      # Top referrers
      @top_referrers = visits
        .where.not(referring_domain: [ nil, "" ])
        .group(:referring_domain)
        .count
        .sort_by { |_, v| -v }
        .first(10)
        .to_h

      # Device breakdown
      @devices = visits
        .group(:device_type)
        .count
        .transform_keys { |k| k || "Unknown" }
    end

    def load_page_views
      page_views = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "page_view")

      @total_page_views = page_views.count

      # Top pages by view count
      @top_pages = page_views
        .select("properties->>'page' as page, COUNT(*) as view_count")
        .group("properties->>'page'")
        .order("view_count DESC")
        .limit(15)
        .map { |r| [ r.page, r.view_count ] }
        .to_h

      # Page views by day for chart
      @page_views_by_day = page_views
        .group("DATE(time)")
        .count
        .transform_keys { |k| k.to_date }
        .sort
        .to_h
    end

    def load_lookup_stats
      # All lookup events
      lookup_events = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: [
          "guest_lookup_performed",
          "user_lookup_performed",
          "extension_lookup_performed"
        ])

      @total_lookups = lookup_events.count

      # Use native PostgreSQL jsonb operators for efficient queries
      user_lookup_base = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "user_lookup_performed")

      photo_count = user_lookup_base.where("properties->>'lookup_type' = ?", "photo").count
      non_photo_count = user_lookup_base.where("properties->>'lookup_type' IS DISTINCT FROM ?", "photo").count

      # Email forwarding (orders created via email)
      @email_lookups = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "order_created")
        .where("properties->>'source' = ?", "email")
        .count

      # Lookups by source
      @lookups_by_source = {
        "Homepage (guest)" => Ahoy::Event.where("time >= ?", @start_date)
          .where(name: "guest_lookup_performed").count,
        "Homepage (user)" => non_photo_count,
        "Extension" => Ahoy::Event.where("time >= ?", @start_date)
          .where(name: "extension_lookup_performed").count,
        "Photo upload" => photo_count
      }

      @lookups_by_source["Email forwarding"] = @email_lookups

      # Lookups by day for chart
      @lookups_by_day = lookup_events
        .group("DATE(time)")
        .count
        .transform_keys { |k| k.to_date }
        .sort
        .to_h
    end

    def load_signup_stats
      # User registrations
      registrations = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "user_registered")

      @total_signups = registrations.count

      # Signups by day
      @signups_by_day = registrations
        .group("DATE(time)")
        .count
        .transform_keys { |k| k.to_date }
        .sort
        .to_h

      # Calculate conversion rate (visitors to signups)
      @signup_conversion_rate = if @total_visitors > 0
        (@total_signups.to_f / @total_visitors * 100).round(2)
      else
        0
      end

      # Also count from User table as backup (in case event tracking wasn't always active)
      @total_users_created = User.where("created_at >= ?", @start_date).count
    end

    def load_usage_trends
      # Active users (users who performed lookups)
      @active_users = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "user_lookup_performed")
        .distinct
        .count(:user_id)

      # Repeat users (more than 1 lookup)
      user_lookup_counts = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "user_lookup_performed")
        .where.not(user_id: nil)
        .group(:user_id)
        .count

      @repeat_users = user_lookup_counts.count { |_, count| count > 1 }

      # Average lookups per active user
      @avg_lookups_per_user = if @active_users > 0
        (user_lookup_counts.values.sum.to_f / @active_users).round(2)
      else
        0
      end

      # Guest limit reached events
      @guest_limits_reached = Ahoy::Event.where("time >= ?", @start_date)
        .where(name: "guest_limit_reached")
        .count
    end
  end
end
