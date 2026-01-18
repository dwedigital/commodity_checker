module Api
  module V1
    class BatchJobsController < BaseController
      before_action :set_request_start_time
      before_action :find_batch_job, only: [ :show ]

      # GET /api/v1/batch-jobs/:id
      # Poll for batch job status and results
      def show
        render_success(@batch_job.to_status_hash)
      end

      # GET /api/v1/batch-jobs
      # List recent batch jobs for the current API key
      def index
        batch_jobs = current_api_key.batch_jobs
                                    .recent
                                    .limit(params[:limit] || 20)
                                    .offset(params[:offset] || 0)

        render_success(
          batch_jobs: batch_jobs.map { |job| job_summary(job) },
          total: current_api_key.batch_jobs.count
        )
      end

      private

      def find_batch_job
        @batch_job = current_api_key.batch_jobs.find_by_public_id!(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error(:not_found, "Batch job not found")
      end

      def job_summary(job)
        {
          batch_id: job.public_id,
          status: job.status,
          total_items: job.total_items,
          completed_items: job.completed_items,
          failed_items: job.failed_items,
          created_at: job.created_at.iso8601,
          completed_at: job.completed_at&.iso8601
        }
      end
    end
  end
end
