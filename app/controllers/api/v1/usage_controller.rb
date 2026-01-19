module Api
  module V1
    class UsageController < BaseController
      # GET /api/v1/usage
      # Get current usage statistics
      def show
        stats = current_api_key.usage_stats

        # Load today's requests once to avoid N+1 queries
        today_requests_relation = current_api_key.api_requests.today
        today_requests_count = today_requests_relation.count
        month_requests = current_api_key.api_requests.this_month.count

        # Response time averages (computed from loaded relation)
        avg_response_time = today_requests_relation
                                           .where.not(response_time_ms: nil)
                                           .average(:response_time_ms)
                                           &.round(1)

        # Success rate (use cached count)
        successful_today = today_requests_relation.successful.count
        success_rate = today_requests_count > 0 ? (successful_today.to_f / today_requests_count * 100).round(1) : 100.0

        # Endpoint breakdown
        endpoint_stats = today_requests_relation
                                        .group(:endpoint)
                                        .count

        render_success(
          api_key: {
            name: current_api_key.name,
            tier: current_api_key.tier,
            created_at: current_api_key.created_at.iso8601
          },
          limits: stats,
          usage: {
            today: today_requests_count,
            this_month: month_requests,
            avg_response_time_ms: avg_response_time,
            success_rate_percent: success_rate
          },
          endpoints: endpoint_stats,
          batch_jobs: {
            total: current_api_key.batch_jobs.count,
            pending: current_api_key.batch_jobs.pending.count,
            processing: current_api_key.batch_jobs.processing.count
          }
        )
      end

      # GET /api/v1/usage/history
      # Get usage history over time
      def history
        days = (params[:days] || 7).to_i.clamp(1, 30)

        daily_stats = (0...days).map do |i|
          date = i.days.ago.to_date
          requests = current_api_key.api_requests
                                    .where(created_at: date.beginning_of_day..date.end_of_day)

          {
            date: date.iso8601,
            total_requests: requests.count,
            successful_requests: requests.successful.count,
            failed_requests: requests.failed.count,
            avg_response_time_ms: requests.where.not(response_time_ms: nil)
                                          .average(:response_time_ms)&.round(1)
          }
        end.reverse

        render_success(
          days: days,
          history: daily_stats
        )
      end
    end
  end
end
