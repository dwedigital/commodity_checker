class ApplicationJob < ActiveJob::Base
  # Discard jobs when the underlying record no longer exists
  discard_on ActiveJob::DeserializationError

  # Automatically retry jobs that encounter transient failures
  # Uses polynomial backoff (3s, 18s, 83s, etc.)
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # Retry on network-related errors with polynomial backoff
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3
end
