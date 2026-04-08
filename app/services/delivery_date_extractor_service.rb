# Extracts expected delivery dates from email content
# Handles:
# 1. Explicit dates - "ESTIMATED DELIVERY DATE: 2026-01-28" or "Arriving January 28"
# 2. Shipping method calculations - "Royal Mail 2nd Class" -> calculate 2-3 business days
# 3. Day range extraction - "3-5 business days" -> use minimum
class DeliveryDateExtractorService
  CONFIDENCE_EXPLICIT_DATE = 0.9
  CONFIDENCE_SHIPPING_METHOD = 0.7
  CONFIDENCE_DAY_RANGE = 0.6

  def self.month_names_pattern
    "Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?"
  end

  def self.day_names_pattern
    "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun"
  end

  attr_reader :email_body, :email_date

  def initialize(email_body:, email_date:)
    @email_body = email_body.to_s
    @email_date = email_date || Date.current
    @shipping_config = load_shipping_config
  end

  def extract
    # Try extraction strategies in order of confidence
    result = try_explicit_date_extraction ||
             try_relative_date_extraction ||
             try_shipping_method_extraction ||
             try_day_range_extraction

    return nil unless result

    # Validate the date is not in the past
    if result[:estimated_delivery] && result[:estimated_delivery] < email_date
      Rails.logger.info("Extracted delivery date #{result[:estimated_delivery]} is before email date #{email_date}, discarding")
      return nil
    end

    result
  end

  private

  def load_shipping_config
    config_path = Rails.root.join("config", "shipping_methods.yml")
    return {} unless File.exist?(config_path)

    YAML.load_file(config_path).deep_symbolize_keys
  rescue => e
    Rails.logger.error("Failed to load shipping_methods.yml: #{e.message}")
    {}
  end

  def try_explicit_date_extraction
    patterns = build_explicit_date_patterns

    patterns.each do |pattern|
      match = email_body.match(pattern)
      next unless match

      date_str = match[1]
      parsed_date = parse_date_string(date_str)

      next unless parsed_date

      return {
        estimated_delivery: parsed_date,
        confidence: CONFIDENCE_EXPLICIT_DATE,
        source: :explicit_date,
        shipping_method: nil,
        raw_match: match[0]
      }
    end

    nil
  end

  def try_relative_date_extraction
    patterns = build_relative_date_patterns

    patterns.each do |pattern|
      match = email_body.match(pattern)
      next unless match

      relative_str = match[1].downcase
      parsed_date = parse_relative_date(relative_str)

      next unless parsed_date

      return {
        estimated_delivery: parsed_date,
        confidence: CONFIDENCE_EXPLICIT_DATE,
        source: :explicit_date,
        shipping_method: nil,
        raw_match: match[0]
      }
    end

    nil
  end

  def build_relative_date_patterns
    day_names = self.class.day_names_pattern

    [
      # "tomorrow", "today"
      /\b(today|tomorrow)\b/i,

      # "this Friday", "next Monday"
      /\b((?:this|next)\s+(?:#{day_names}))\b/i
    ]
  end

  def try_shipping_method_extraction
    return nil if @shipping_config.empty?

    # First, try carrier-specific methods
    carriers = @shipping_config[:carriers] || {}
    carriers.each do |carrier_name, carrier_config|
      carrier_patterns = carrier_config[:patterns] || []
      next unless carrier_patterns.any? { |p| email_body.downcase.include?(p.downcase) }

      methods = carrier_config[:methods] || {}
      methods.each do |method_name, method_config|
        method_patterns = method_config[:patterns] || []
        next unless method_patterns.any? { |p| email_body.downcase.include?(p.downcase) }

        min_days = method_config[:min_days] || 1
        delivery_date = add_business_days(email_date, min_days)

        matched_pattern = method_patterns.find { |p| email_body.downcase.include?(p.downcase) }

        return {
          estimated_delivery: delivery_date,
          confidence: CONFIDENCE_SHIPPING_METHOD,
          source: :shipping_method,
          shipping_method: "#{carrier_name}/#{method_name}",
          raw_match: matched_pattern
        }
      end
    end

    # Fall back to generic methods
    generic_methods = @shipping_config[:generic_methods] || {}
    generic_methods.each do |method_name, method_config|
      method_patterns = method_config[:patterns] || []
      next unless method_patterns.any? { |p| email_body.downcase.include?(p.downcase) }

      min_days = method_config[:min_days] || 1
      delivery_date = add_business_days(email_date, min_days)

      matched_pattern = method_patterns.find { |p| email_body.downcase.include?(p.downcase) }

      return {
        estimated_delivery: delivery_date,
        confidence: CONFIDENCE_SHIPPING_METHOD - 0.1, # Slightly lower for generic
        source: :shipping_method,
        shipping_method: "generic/#{method_name}",
        raw_match: matched_pattern
      }
    end

    nil
  end

  def try_day_range_extraction
    return nil if @shipping_config.empty?

    day_range_patterns = @shipping_config[:day_range_patterns] || []

    day_range_patterns.each do |pattern_str|
      pattern = Regexp.new(pattern_str, Regexp::IGNORECASE)
      match = email_body.match(pattern)
      next unless match

      # Extract minimum days (first capture group)
      min_days = match[1].to_i
      next if min_days <= 0 || min_days > 30

      delivery_date = add_business_days(email_date, min_days)

      return {
        estimated_delivery: delivery_date,
        confidence: CONFIDENCE_DAY_RANGE,
        source: :day_range,
        shipping_method: nil,
        raw_match: match[0]
      }
    end

    nil
  end

  def build_explicit_date_patterns
    month_names = self.class.month_names_pattern
    day_names = self.class.day_names_pattern

    [
      # ISO format: 2026-01-28
      /(?:estimated\s+)?(?:delivery|arrival|arriving|deliver(?:ed)?)\s*(?:date|by)?[:\s]+(\d{4}-\d{2}-\d{2})/i,

      # UK format: 28/01/2026 or 28-01-2026
      /(?:estimated\s+)?(?:delivery|arrival|arriving|deliver(?:ed)?)\s*(?:date|by)?[:\s]+(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4})/i,

      # Natural language with year: "January 28, 2026"
      /(?:estimated\s+)?(?:delivery|arrival|arriving|arrives?|deliver(?:ed)?|expected)\s*(?:date|by)?[:\s]*((?:#{month_names})\s+\d{1,2}(?:st|nd|rd|th)?,?\s*\d{4})/i,
      /(?:estimated\s+)?(?:delivery|arrival|arriving|arrives?|deliver(?:ed)?|expected)\s*(?:date|by)?[:\s]*(\d{1,2}(?:st|nd|rd|th)?\s+(?:#{month_names}),?\s*\d{4})/i,

      # Natural language without year: "Arriving January 28"
      /(?:arriving|arrives?|expected|delivery)[:\s]*((?:#{month_names})\s+\d{1,2}(?:st|nd|rd|th)?)\b/i,
      /(?:arriving|arrives?|expected|delivery)[:\s]*(\d{1,2}(?:st|nd|rd|th)?\s+(?:#{month_names}))\b/i,

      # "by January 28" or "on January 28"
      /\b(?:by|on)\s+((?:#{month_names})\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{4})?)/i,
      /\b(?:by|on)\s+(\d{1,2}(?:st|nd|rd|th)?\s+(?:#{month_names})(?:,?\s*\d{4})?)/i,

      # Day of week: "Arriving Friday"
      /(?:arriving|arrives?|expected|delivery)\s*(?:on)?\s*(#{day_names})/i
    ]
  end

  def parse_date_string(date_str)
    return nil if date_str.blank?

    # Clean up ordinal suffixes
    cleaned = date_str.gsub(/(\d+)(?:st|nd|rd|th)/, '\1')

    # Try various parsing approaches
    begin
      # ISO format
      return Date.parse(cleaned) if cleaned.match?(/^\d{4}-\d{2}-\d{2}$/)

      # UK format (dd/mm/yyyy)
      if match = cleaned.match(%r{^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$})
        day, month, year = match[1].to_i, match[2].to_i, match[3].to_i
        return Date.new(year, month, day)
      end

      # Day of week only
      day_names = %w[sunday monday tuesday wednesday thursday friday saturday sun mon tue wed thu fri sat]
      if day_names.any? { |d| cleaned.downcase.include?(d) }
        return parse_day_of_week(cleaned)
      end

      # Natural language date
      parsed = Date.parse(cleaned)

      # If no year was specified and parsed date is in the past, assume next year
      unless date_str.match?(/\d{4}/)
        if parsed < email_date
          parsed = parsed.next_year
        end
      end

      parsed
    rescue ArgumentError, Date::Error
      nil
    end
  end

  def parse_relative_date(relative_str)
    case relative_str.downcase
    when "today"
      email_date
    when "tomorrow"
      email_date + 1.day
    else
      # "this Friday", "next Monday"
      if match = relative_str.match(/(this|next)\s+(\w+)/i)
        modifier = match[1].downcase
        day_name = match[2].downcase

        target_wday = day_name_to_wday(day_name)
        return nil unless target_wday

        current_wday = email_date.wday
        days_until = (target_wday - current_wday) % 7
        # For "next X" when today is X, go to next week
        days_until = 7 if days_until == 0 && modifier == "next"

        email_date + days_until.days
      end
    end
  end

  def parse_day_of_week(day_str)
    target_wday = day_name_to_wday(day_str)
    return nil unless target_wday

    current_wday = email_date.wday
    days_until = (target_wday - current_wday) % 7
    days_until = 7 if days_until == 0 # If today, assume next week

    email_date + days_until.days
  end

  def day_name_to_wday(name)
    mapping = {
      "sunday" => 0, "sun" => 0,
      "monday" => 1, "mon" => 1,
      "tuesday" => 2, "tue" => 2,
      "wednesday" => 3, "wed" => 3,
      "thursday" => 4, "thu" => 4,
      "friday" => 5, "fri" => 5,
      "saturday" => 6, "sat" => 6
    }
    mapping[name.downcase.strip]
  end

  def add_business_days(start_date, num_days)
    return start_date if num_days <= 0

    current_date = start_date
    days_added = 0

    while days_added < num_days
      current_date += 1.day
      # Skip weekends (Saturday = 6, Sunday = 0)
      days_added += 1 unless current_date.saturday? || current_date.sunday?
    end

    current_date
  end
end
