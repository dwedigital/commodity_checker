class ApplicationMailer < ActionMailer::Base
  default from: "noreply@tariffik.com"
  layout "mailer"

  # Email has to carry its styling inline, so the templates reach for these.
  helper MailerHelper
end
