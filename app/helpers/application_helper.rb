module ApplicationHelper
  def workspace_page?
    request.path.start_with?("/dashboard") || (devise_controller? && user_signed_in?)
  end

  # Sign-in screens and the extension consent flow share the dotted auth ground.
  def auth_page?
    devise_controller? || controller_name == "extension_auth"
  end

  # Splits an HS code into heading / subheading / national digits ("6109 10 0010"),
  # wrapping the subheading pair so .tf-code can mark it in red.
  def commodity_code_display(code)
    digits = code.to_s.gsub(/\D/, "")
    return code.to_s if digits.length < 6

    safe_join([ digits[0, 4], " ", tag.span(digits[4, 2]), (" #{digits[6..]}" if digits.length > 6) ].compact)
  end

  ORDER_STATUS_BADGES = {
    "pending" => [ "Pending", "tf-badge-neutral" ],
    "in_transit" => [ "In transit", "tf-badge-muted" ],
    "delivered" => [ "Delivered", "tf-badge-success" ]
  }.freeze

  LOOKUP_STATUS_BADGES = {
    "pending" => [ "Processing", "tf-badge-muted" ],
    "completed" => [ "Complete", "tf-badge-success" ],
    "partial" => [ "Partial data", "tf-badge-neutral" ],
    "failed" => [ "Failed", "tf-badge-danger" ]
  }.freeze

  def order_status_badge(order)
    label, variant = ORDER_STATUS_BADGES.fetch(order.status.to_s) { [ order.status.to_s.humanize, "tf-badge-neutral" ] }
    tag.span(label, class: "tf-badge #{variant}")
  end

  def lookup_status_badge(lookup, **options)
    return if lookup.scrape_status.blank?

    label, variant = LOOKUP_STATUS_BADGES.fetch(lookup.scrape_status.to_s) { [ lookup.scrape_status.to_s.humanize, "tf-badge-neutral" ] }
    tag.span(label, class: "tf-badge #{variant}", **options)
  end

  def lookup_type_label(lookup)
    lookup.url? ? "URL lookup" : "#{lookup.lookup_type.humanize} lookup"
  end

  def workspace_navigation
    [
      [ "Dashboard", dashboard_path, request.path == dashboard_path ],
      [ "Lookups", product_lookups_path, controller_name == "product_lookups" ],
      [ "Orders", orders_path, controller_name == "orders" ],
      [ "API", developer_path, controller_name == "developer" ],
      [ "Settings", edit_user_registration_path, devise_controller? && user_signed_in? ]
    ]
  end
end
