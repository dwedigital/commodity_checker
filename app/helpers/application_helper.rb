module ApplicationHelper
  # The MCP endpoint, as a client should be pointed at it. Built from the request
  # so it is correct on localhost and on tariffik.com without configuration.
  def mcp_url
    "#{request.base_url}/mcp"
  end

  # The north-east arrow, drawn rather than typed.
  #
  # U+2197 was the glyph here, but no font this site asks for contains it
  # (Arial, Helvetica and the Google Fonts latin subsets all lack it), so every
  # arrow fell through to whatever the OS offered. U+2197 also has an emoji
  # presentation, and on iOS the first fallback font carrying it is Apple Color
  # Emoji — so the marks rendered as a blue emoji arrow on iPhone. An inline SVG
  # depends on no font at all.
  #
  # It inherits colour through currentColor and scales with the text through the
  # 1em box in .tf-arrow, so it drops in wherever the character used to sit.
  def tf_arrow(classes: nil)
    tag.svg(
      tag.path(nil, d: "M7 17 17 7M9 7h8v8", fill: "none", stroke: "currentColor",
                    "stroke-width": "2.2", "stroke-linecap": "round", "stroke-linejoin": "round"),
      class: [ "tf-arrow", classes ].compact.join(" "),
      viewBox: "0 0 24 24",
      "aria-hidden": "true",
      focusable: "false"
    )
  end

  def workspace_page?
    request.path.start_with?("/dashboard") || (devise_controller? && user_signed_in?)
  end

  # Sign-in screens and the extension consent flow share the dotted auth ground.
  def auth_page?
    devise_controller? || controller_name.in?(%w[sessions extension_auth authorizations])
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
      [ "Settings", account_path, controller_name == "accounts" ]
    ]
  end
end
