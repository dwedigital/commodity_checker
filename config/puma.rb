# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Calculate workers based on available memory (production only)
# Each worker uses ~300-500MB, so we allocate 512MB per worker to be safe
# Can be overridden with WEB_CONCURRENCY env var
if ENV["RAILS_ENV"] == "production"
  def calculate_workers
    # Check if explicitly set
    return ENV["WEB_CONCURRENCY"].to_i if ENV["WEB_CONCURRENCY"]

    # Try to detect available memory (Linux)
    if File.exist?("/proc/meminfo")
      meminfo = File.read("/proc/meminfo")
      if meminfo =~ /MemTotal:\s+(\d+)\s+kB/
        total_memory_mb = $1.to_i / 1024
        # Reserve 512MB for system, allocate 512MB per worker, max 8 workers
        workers = [ (total_memory_mb - 512) / 512, 1 ].max
        return [ workers, 8 ].min
      end
    end

    # Default to 2 workers if we can't detect memory
    2
  end

  workers calculate_workers

  # Preload app for faster worker boot and memory savings via copy-on-write
  preload_app!
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
