# Service for handling commodity code lookups from the browser extension
# Supports both anonymous (limited) and authenticated lookups
class ExtensionLookupService
  def initialize(api_service: ApiCommodityService.new)
    @api_service = api_service
  end

  # Perform an anonymous lookup (limited to 3 lifetime lookups per extension)
  def anonymous_lookup(extension_id:, url: nil, description: nil, product: nil, ip_address: nil)
    # Check if extension can still make anonymous lookups
    unless ExtensionLookup.can_perform_anonymous_lookup?(extension_id)
      return {
        error: "free_lookups_exhausted",
        message: "You've used all 3 free lookups. Sign in to continue using Tariffik.",
        extension_usage: {
          used: ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT,
          remaining: 0,
          limit: ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT,
          type: "anonymous"
        }
      }
    end

    # Perform the actual lookup
    result = perform_lookup(url: url, description: description, product: product)

    if result[:error]
      return result.merge(
        extension_usage: anonymous_usage_stats(extension_id)
      )
    end

    # Record the anonymous lookup
    ExtensionLookup.record_anonymous_lookup(
      extension_id: extension_id,
      url: url,
      commodity_code: result[:commodity_code],
      ip_address: ip_address
    )

    result.merge(
      extension_usage: anonymous_usage_stats(extension_id)
    )
  end

  # Perform an authenticated lookup (respects user's subscription tier limits)
  def authenticated_lookup(user:, url: nil, description: nil, product: nil, save_to_account: true)
    # Check if user can make more lookups
    unless user.can_perform_extension_lookup?
      return {
        error: "monthly_limit_reached",
        message: "You've reached your monthly lookup limit. Upgrade your subscription for more lookups.",
        user_usage: user_usage_stats(user)
      }
    end

    # Perform the actual lookup
    result = perform_lookup(url: url, description: description, product: product)

    if result[:error]
      return result.merge(user_usage: user_usage_stats(user))
    end

    # Save to user's ProductLookup if requested
    if save_to_account
      product_lookup = create_product_lookup(user: user, url: url, description: description, result: result)
      result[:product_lookup_id] = product_lookup.id if product_lookup
    end

    result.merge(user_usage: user_usage_stats(user))
  end

  private

  def perform_lookup(url: nil, description: nil, product: nil)
    if url.present?
      @api_service.suggest_from_url(url)
    elsif description.present? || product.present?
      desc = description.presence || build_description_from_product(product)
      @api_service.suggest_from_description(desc)
    else
      { error: "Either URL or product description is required" }
    end
  end

  def build_description_from_product(product)
    return nil if product.blank?

    parts = []
    parts << product[:title] if product[:title].present?
    parts << "Brand: #{product[:brand]}" if product[:brand].present?
    parts << product[:description] if product[:description].present?
    parts.join(". ").presence
  end

  def anonymous_usage_stats(extension_id)
    {
      used: ExtensionLookup.anonymous_lookups_count(extension_id),
      remaining: ExtensionLookup.anonymous_lookups_remaining(extension_id),
      limit: ExtensionLookup::ANONYMOUS_LIFETIME_LIMIT,
      type: "anonymous"
    }
  end

  def user_usage_stats(user)
    {
      used: user.extension_lookups_this_month,
      remaining: user.extension_lookups_remaining,
      limit: user.extension_lookup_limit == Float::INFINITY ? "unlimited" : user.extension_lookup_limit,
      tier: user.subscription_tier,
      type: "authenticated"
    }
  end

  def create_product_lookup(user:, url:, description:, result:)
    scraped = result[:scraped_product] || {}

    ProductLookup.create!(
      user: user,
      url: url,
      lookup_type: url.present? ? :url : :description,
      title: scraped[:title],
      description: description || scraped[:description],
      brand: scraped[:brand],
      category: scraped[:category] || result[:category],
      material: scraped[:material],
      image_url: scraped[:image_url],
      retailer_name: scraped[:retailer],
      suggested_commodity_code: result[:commodity_code],
      commodity_code_confidence: result[:confidence],
      llm_reasoning: result[:reasoning],
      scrape_status: url.present? ? :completed : nil,
      scraped_at: url.present? ? Time.current : nil
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to create ProductLookup from extension: #{e.message}")
    nil
  end
end
