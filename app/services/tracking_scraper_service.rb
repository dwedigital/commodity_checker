class TrackingScraperService
  CARRIER_HANDLERS = {
    "royal_mail" => :scrape_royal_mail,
    "dhl" => :scrape_dhl,
    "ups" => :scrape_ups,
    "fedex" => :scrape_fedex,
    "amazon" => :scrape_amazon,
    "dpd" => :scrape_dpd,
    "hermes" => :scrape_evri,
    "evri" => :scrape_evri,
    "yodel" => :scrape_yodel,
    "unknown" => :scrape_generic
  }.freeze

  # Status mappings to normalize across carriers
  STATUS_MAPPINGS = {
    delivered: ["delivered", "delivery complete", "signed for", "collected"],
    out_for_delivery: ["out for delivery", "with driver", "on vehicle"],
    in_transit: ["in transit", "on its way", "dispatched", "shipped", "en route", "departed", "arrived at"],
    processing: ["processing", "label created", "shipment information received", "pending"],
    exception: ["exception", "failed delivery", "returned", "held", "delayed"]
  }.freeze

  def initialize
    @conn = Faraday.new do |f|
      f.options.timeout = 15
      f.options.open_timeout = 10
      f.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
      f.response :follow_redirects, limit: 3
      f.adapter Faraday.default_adapter
    end
  end

  def scrape(tracking_url, carrier: "unknown")
    return nil if tracking_url.blank?

    handler = CARRIER_HANDLERS[carrier.to_s.downcase] || :scrape_generic

    result = send(handler, tracking_url)
    result[:scraped_at] = Time.current if result
    result
  rescue => e
    Rails.logger.error("Tracking scrape failed for #{tracking_url}: #{e.message}")
    { status: "error", error: e.message, scraped_at: Time.current }
  end

  def extract_tracking_number(url)
    # Try to extract tracking number from URL
    patterns = [
      /tracking[_-]?(?:number|id|no)?[=\/]([A-Z0-9]+)/i,
      /track[=\/]([A-Z0-9]+)/i,
      /shipment[=\/]([A-Z0-9]+)/i,
      /\b([A-Z]{2}\d{9}[A-Z]{2})\b/,  # International format (e.g., Royal Mail)
      /\b(1Z[A-Z0-9]{16})\b/i,        # UPS
      /\b(\d{12,22})\b/                # Generic numeric
    ]

    patterns.each do |pattern|
      match = url.match(pattern)
      return match[1] if match
    end

    nil
  end

  private

  def scrape_royal_mail(url)
    tracking_number = extract_tracking_number(url)

    # Royal Mail tracking page
    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    parse_royal_mail_html(html, tracking_number)
  rescue Faraday::Error => e
    Rails.logger.warn("Royal Mail scrape failed: #{e.message}")
    nil
  end

  def parse_royal_mail_html(html, tracking_number)
    status = extract_status_from_html(html)
    location = html.match(/(?:location|office)[:\s]*([^<\n]+)/i)&.[](1)&.strip
    date = extract_date_from_html(html)

    {
      carrier: "Royal Mail",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: location,
      last_update: date,
      raw_snippet: html[0..500]
    }
  end

  def scrape_dhl(url)
    tracking_number = extract_tracking_number(url)

    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    status = extract_status_from_html(html)

    {
      carrier: "DHL",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: extract_location_from_html(html),
      last_update: extract_date_from_html(html),
      raw_snippet: html[0..500]
    }
  rescue Faraday::Error => e
    Rails.logger.warn("DHL scrape failed: #{e.message}")
    nil
  end

  def scrape_ups(url)
    tracking_number = extract_tracking_number(url)

    # UPS tracking pages are heavily JS-based
    # Try to get basic info from URL or redirect
    response = @conn.get(url)

    {
      carrier: "UPS",
      tracking_number: tracking_number,
      status: "Check carrier website",
      normalized_status: :unknown,
      tracking_url: url,
      note: "UPS requires JavaScript - please check tracking link directly"
    }
  rescue Faraday::Error => e
    Rails.logger.warn("UPS scrape failed: #{e.message}")
    nil
  end

  def scrape_fedex(url)
    tracking_number = extract_tracking_number(url)

    {
      carrier: "FedEx",
      tracking_number: tracking_number,
      status: "Check carrier website",
      normalized_status: :unknown,
      tracking_url: url,
      note: "FedEx requires JavaScript - please check tracking link directly"
    }
  rescue Faraday::Error
    nil
  end

  def scrape_amazon(url)
    # Amazon tracking is behind login
    {
      carrier: "Amazon",
      status: "Check Amazon account",
      normalized_status: :unknown,
      tracking_url: url,
      note: "Amazon tracking requires login - please check your Amazon account"
    }
  end

  def scrape_dpd(url)
    tracking_number = extract_tracking_number(url)

    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    status = extract_status_from_html(html)

    {
      carrier: "DPD",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: extract_location_from_html(html),
      last_update: extract_date_from_html(html),
      raw_snippet: html[0..500]
    }
  rescue Faraday::Error => e
    Rails.logger.warn("DPD scrape failed: #{e.message}")
    nil
  end

  def scrape_evri(url)
    tracking_number = extract_tracking_number(url)

    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    status = extract_status_from_html(html)

    {
      carrier: "Evri",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: extract_location_from_html(html),
      last_update: extract_date_from_html(html),
      raw_snippet: html[0..500]
    }
  rescue Faraday::Error => e
    Rails.logger.warn("Evri scrape failed: #{e.message}")
    nil
  end

  def scrape_yodel(url)
    tracking_number = extract_tracking_number(url)

    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    status = extract_status_from_html(html)

    {
      carrier: "Yodel",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: extract_location_from_html(html),
      last_update: extract_date_from_html(html),
      raw_snippet: html[0..500]
    }
  rescue Faraday::Error => e
    Rails.logger.warn("Yodel scrape failed: #{e.message}")
    nil
  end

  def scrape_generic(url)
    response = @conn.get(url)
    return nil unless response.success?

    html = response.body
    tracking_number = extract_tracking_number(url)
    status = extract_status_from_html(html)

    {
      carrier: detect_carrier_from_html(html) || "Unknown",
      tracking_number: tracking_number,
      status: status,
      normalized_status: normalize_status(status),
      location: extract_location_from_html(html),
      last_update: extract_date_from_html(html),
      raw_snippet: html[0..500]
    }
  rescue Faraday::Error => e
    Rails.logger.warn("Generic scrape failed: #{e.message}")
    nil
  end

  def extract_status_from_html(html)
    # Common patterns for tracking status
    patterns = [
      /<[^>]*class="[^"]*status[^"]*"[^>]*>([^<]+)</i,
      /status[:\s]*<[^>]*>([^<]+)</i,
      /(?:current\s+)?status[:\s]*([^<\n]+)/i,
      /(?:parcel|package|shipment)\s+(?:is\s+)?([^<\n.]+)/i,
      /tracking[:\s]*([^<\n]+delivered[^<\n]*)/i,
      /tracking[:\s]*([^<\n]+transit[^<\n]*)/i
    ]

    patterns.each do |pattern|
      match = html.match(pattern)
      if match
        status = match[1].strip.gsub(/\s+/, " ")
        return status if status.length > 3 && status.length < 100
      end
    end

    "Status unavailable"
  end

  def extract_location_from_html(html)
    patterns = [
      /(?:current\s+)?location[:\s]*([^<\n]+)/i,
      /(?:last\s+)?(?:seen\s+)?(?:at|in)[:\s]*([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/,
      /depot[:\s]*([^<\n]+)/i
    ]

    patterns.each do |pattern|
      match = html.match(pattern)
      if match
        location = match[1].strip
        return location if location.length > 2 && location.length < 100
      end
    end

    nil
  end

  def extract_date_from_html(html)
    # Look for date patterns
    patterns = [
      /(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/,
      /(\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{2,4})/i,
      /((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4})/i
    ]

    patterns.each do |pattern|
      match = html.match(pattern)
      return match[1] if match
    end

    nil
  end

  def detect_carrier_from_html(html)
    carrier_patterns = {
      "Royal Mail" => /royal\s*mail/i,
      "Parcelforce" => /parcelforce/i,
      "DHL" => /\bDHL\b/,
      "UPS" => /\bUPS\b/,
      "FedEx" => /fedex/i,
      "DPD" => /\bDPD\b/,
      "Evri" => /evri|hermes/i,
      "Yodel" => /yodel/i,
      "Amazon" => /amazon/i
    }

    carrier_patterns.each do |name, pattern|
      return name if html.match?(pattern)
    end

    nil
  end

  def normalize_status(status_text)
    return :unknown if status_text.blank?

    status_lower = status_text.downcase

    STATUS_MAPPINGS.each do |normalized, keywords|
      return normalized if keywords.any? { |kw| status_lower.include?(kw) }
    end

    :unknown
  end
end
