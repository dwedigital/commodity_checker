# frozen_string_literal: true

# Inline styles for transactional email.
#
# Email clients strip <style> blocks, so every rule has to ride on the element.
# The values are the September 2026 Tariffik palette: paper #f8f7f2, ink #292725,
# muted #67645e, hairline #dddcd4, red #d93120.
module MailerHelper
  PAPER = "#f8f7f2"
  CARD = "#fffefa"
  INK = "#292725"
  MUTED = "#67645e"
  LINE = "#d8d4c6"
  RED = "#d93120"

  # Space Grotesk will not load in most clients, so it leads a stack that falls
  # back to whatever the client has.
  FONT = "'Space Grotesk', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
  MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"

  def email_eyebrow_style
    "margin:0 0 12px; font-family:#{MONO}; font-size:10px; font-weight:500; " \
      "letter-spacing:1.5px; text-transform:uppercase; color:#{MUTED};"
  end

  def email_heading_style
    "margin:0 0 18px; font-family:#{FONT}; font-size:25px; font-weight:500; " \
      "letter-spacing:-0.9px; line-height:1.2; color:#{INK};"
  end

  def email_text_style
    "margin:0 0 16px; font-family:#{FONT}; font-size:15px; line-height:1.65; color:#{INK};"
  end

  def email_muted_style
    "margin:0 0 14px; font-family:#{FONT}; font-size:13px; line-height:1.6; color:#{MUTED};"
  end

  def email_link_style
    "color:#{RED}; text-decoration:underline; word-break:break-all;"
  end

  # A 6px rounded rectangle, never a pill, matching the buttons on the site.
  def email_button(label, url)
    link_to label, url, style: "display:inline-block; background:#{RED}; color:#ffffff; " \
      "text-decoration:none; padding:14px 24px; border-radius:6px; font-family:#{FONT}; " \
      "font-size:13px; font-weight:600; letter-spacing:0.2px;"
  end

  def email_rule_style
    "border:0; border-top:1px solid #{LINE}; margin:26px 0 20px;"
  end
end
