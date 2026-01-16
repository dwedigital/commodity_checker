class GuestLookup < ApplicationRecord
  validates :guest_token, presence: true
  validates :lookup_type, presence: true, inclusion: { in: %w[url photo] }

  scope :for_token, ->(token) { where(guest_token: token) }
  scope :within_window, ->(hours = 168) { where(created_at: hours.hours.ago..) }
  scope :recent, -> { order(created_at: :desc) }

  # Analytics scopes
  scope :today, -> { where(created_at: Time.current.beginning_of_day..) }
  scope :this_week, -> { where(created_at: 1.week.ago..) }
  scope :this_month, -> { where(created_at: 1.month.ago..) }

  def self.count_for_token(token, window_hours: 168)
    for_token(token).within_window(window_hours).count
  end

  # Analytics methods
  def self.total_count
    count
  end

  def self.unique_guests
    distinct.count(:guest_token)
  end

  def self.by_lookup_type
    group(:lookup_type).count
  end

  def self.daily_counts(days: 30)
    where(created_at: days.days.ago..)
      .group("DATE(created_at)")
      .count
      .transform_keys { |k| k.to_date }
  end
end
