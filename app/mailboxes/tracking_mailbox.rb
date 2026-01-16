class TrackingMailbox < ApplicationMailbox
  before_processing :find_user

  def process
    return bounce_with_no_user unless @user

    inbound_email_record = create_inbound_email_record
    ProcessInboundEmailJob.perform_later(inbound_email_record.id)
  end

  private

  def find_user
    # Extract token from the "to" address (e.g., track-abc123@domain.com)
    to_address = mail.to&.first || mail.recipients&.first
    return unless to_address

    token = extract_token(to_address)
    @user = User.find_by(inbound_email_token: token) if token
  end

  def extract_token(email_address)
    # Match track-{token}@domain pattern
    match = email_address.match(/^track-([a-f0-9]+)@/i)
    match[1] if match
  end

  def create_inbound_email_record
    @user.inbound_emails.create!(
      subject: mail.subject || "(No subject)",
      from_address: mail.from&.first || "unknown",
      body_text: extract_body_text,
      body_html: extract_body_html,
      processing_status: :received
    )
  end

  def extract_body_text
    if mail.multipart?
      # Prefer plain text, fall back to HTML stripped of tags
      plain_part = mail.text_part
      html_part = mail.html_part

      if plain_part
        plain_part.decoded
      elsif html_part
        strip_html(html_part.decoded)
      else
        mail.body.decoded
      end
    else
      mail.body.decoded
    end
  rescue => e
    Rails.logger.error("Failed to extract email body: #{e.message}")
    ""
  end

  def extract_body_html
    if mail.multipart?
      html_part = mail.html_part
      html_part&.decoded
    elsif mail.content_type&.include?("text/html")
      mail.body.decoded
    end
  rescue => e
    Rails.logger.error("Failed to extract HTML body: #{e.message}")
    nil
  end

  def strip_html(html)
    # Basic HTML stripping - remove tags and decode entities
    html.gsub(/<[^>]+>/, " ")
        .gsub(/&nbsp;/, " ")
        .gsub(/&amp;/, "&")
        .gsub(/&lt;/, "<")
        .gsub(/&gt;/, ">")
        .gsub(/\s+/, " ")
        .strip
  end

  def bounce_with_no_user
    Rails.logger.warn("Received email for unknown user token: #{mail.to}")
    # In production, you might want to send a bounce email
  end
end
