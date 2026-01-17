# Puma Worker Auto-Detection Implementation

## Overview

Enhanced Puma configuration to automatically detect and set the optimal number of worker processes based on available system memory in production. This eliminates the need to manually configure `WEB_CONCURRENCY` for each deployment environment.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Memory detection | `/proc/meminfo` | Standard Linux interface, works on Render/Heroku/Docker |
| Memory per worker | 512MB | Conservative estimate for Rails app with headroom |
| System reserve | 512MB | Leave room for OS, background processes |
| Max workers | 8 | Diminishing returns beyond this, caps resource usage |
| Default fallback | 2 workers | Safe default if memory detection fails |
| Production only | `RAILS_ENV == "production"` | Development uses single process for easier debugging |

## Database Changes

None - configuration only.

## Modified Files

| File | Change |
|------|--------|
| `config/puma.rb` | Added worker auto-detection logic and `preload_app!` |

## Configuration Logic

### Worker Calculation Formula

```ruby
workers = [(total_memory_mb - 512) / 512, 1].max
workers = [workers, 8].min  # Cap at 8
```

### Memory to Worker Mapping

| Total RAM | Reserved | Available | Workers |
|-----------|----------|-----------|---------|
| 512MB | 512MB | 0MB | 1 (minimum) |
| 1GB | 512MB | 512MB | 1 |
| 2GB | 512MB | 1.5GB | 3 |
| 4GB | 512MB | 3.5GB | 7 |
| 8GB+ | 512MB | 7.5GB+ | 8 (max) |

## Code Implementation

```ruby
# config/puma.rb (production section)
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
        workers = [(total_memory_mb - 512) / 512, 1].max
        return [workers, 8].min
      end
    end

    # Default to 2 workers if we can't detect memory
    2
  end

  workers calculate_workers
  preload_app!
end
```

## Additional Optimizations

### preload_app!

Enabled `preload_app!` in production which:
- Loads the application before forking workers
- Enables copy-on-write memory sharing between workers
- Reduces total memory footprint
- Speeds up worker boot time after the initial load

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `WEB_CONCURRENCY` | Override auto-detected worker count | Auto-detected |
| `RAILS_MAX_THREADS` | Threads per worker | 3 |

## Testing/Verification

### Check Current Worker Count

After deployment, check logs for:
```
* Booting worker with pid: 123
* Booting worker with pid: 124
* Booting worker with pid: 125
```

The number of "Booting worker" lines indicates the worker count.

### Verify Memory Detection

```bash
# On Linux/Render
cat /proc/meminfo | grep MemTotal

# Calculate expected workers
# (MemTotal_kB / 1024 - 512) / 512
```

### Override for Testing

```bash
# Set explicit worker count
WEB_CONCURRENCY=4 bin/rails server
```

## Render-Specific Notes

### Instance Types

| Render Plan | RAM | Expected Workers |
|-------------|-----|------------------|
| Starter | 512MB | 1 |
| Starter Plus | 1GB | 1 |
| Standard | 2GB | 3 |
| Standard Plus | 4GB | 7 |
| Pro | 8GB | 8 |

### Scaling Recommendations

- **Low traffic**: Starter Plus (1GB) with 1 worker, 3 threads
- **Medium traffic**: Standard (2GB) with 3 workers
- **High traffic**: Standard Plus (4GB) with 7 workers

## Limitations & Future Improvements

### Current Limitations

- Only works on Linux (requires `/proc/meminfo`)
- Doesn't account for other processes on the same machine
- Fixed 512MB per worker may not suit all apps

### Potential Future Enhancements

- Detect available CPU cores and factor into calculation
- Add memory monitoring and dynamic scaling
- Configure different memory allocation for different environments
- Add health checks for worker memory usage
