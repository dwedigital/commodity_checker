class ApplicationMailbox < ActionMailbox::Base
  # Route emails to track-{token}@domain to the tracking mailbox
  routing /^track-/i => :tracking
end
