class TestEmailsController < ApplicationController
  before_action :authenticate_user!

  def new
  end

  def create
    # Create a simulated inbound email
    inbound_email = current_user.inbound_emails.create!(
      subject: params[:subject].presence || "(No subject)",
      from_address: params[:from_address].presence || "test@example.com",
      body_text: params[:body_text],
      processing_status: :received
    )

    # Process it immediately (or queue for background)
    ProcessInboundEmailJob.perform_later(inbound_email.id)

    redirect_to dashboard_path, notice: "Test email submitted for processing. Check your orders shortly."
  end
end
