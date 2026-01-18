module Api
  module V1
    class CommodityCodesController < BaseController
      before_action :set_request_start_time

      # GET /api/v1/commodity-codes/search
      # Search UK Trade Tariff API for commodity codes
      def search
        query = params[:q] || params[:query]

        if query.blank?
          return render_error(:bad_request, "Query parameter 'q' is required")
        end

        results = TariffLookupService.new.search(query)

        render_success(
          results: results.map { |r| format_search_result(r) },
          query: query,
          count: results.size
        )
      end

      # GET /api/v1/commodity-codes/:code
      # Get details for a specific commodity code
      def show
        code = params[:id].to_s.gsub(/[\s.-]/, "")

        if code.blank? || code.length < 6
          return render_error(:bad_request, "Valid commodity code is required (minimum 6 digits)")
        end

        commodity = TariffLookupService.new.get_commodity(code)

        if commodity.nil?
          return render_error(:not_found, "Commodity code #{code} not found")
        end

        render_success(format_commodity(commodity))
      end

      # POST /api/v1/commodity-codes/suggest
      # AI suggestion from product description
      def suggest
        description = params[:description]

        if description.blank?
          return render_error(:bad_request, "Parameter 'description' is required")
        end

        result = ApiCommodityService.new.suggest_from_description(description)

        if result[:error]
          return render_error(:unprocessable_entity, result[:error])
        end

        render_success(format_suggestion(result))
      end

      # POST /api/v1/commodity-codes/suggest-from-url
      # Async: Scrape URL and suggest commodity code
      def suggest_from_url
        url = params[:url]
        webhook_url = params[:webhook_url]

        if url.blank?
          return render_error(:bad_request, "Parameter 'url' is required")
        end

        unless valid_url?(url)
          return render_error(:bad_request, "Invalid URL format")
        end

        # Create a batch job with single item
        batch_job = create_single_item_batch(url: url, webhook_url: webhook_url)

        # Enqueue processing
        ApiBatchProcessingJob.perform_later(batch_job.id)

        render_success({
          job_id: batch_job.public_id,
          status: "processing",
          poll_url: "/api/v1/batch-jobs/#{batch_job.public_id}",
          webhook_url: webhook_url
        }, status: :accepted)
      end

      # POST /api/v1/commodity-codes/batch
      # Batch processing of multiple items
      def batch
        items = params[:items]
        webhook_url = params[:webhook_url]

        if items.blank? || !items.is_a?(Array)
          return render_error(:bad_request, "Parameter 'items' must be a non-empty array")
        end

        max_batch_size = current_api_key.batch_size_limit
        if items.size > max_batch_size
          return render_error(:bad_request,
            "Batch size exceeds limit. Maximum: #{max_batch_size}, provided: #{items.size}")
        end

        # Validate items
        validation_errors = validate_batch_items(items)
        if validation_errors.any?
          return render_error(:bad_request, "Invalid items in batch", errors: validation_errors)
        end

        # Create batch job
        batch_job = create_batch_job(items: items, webhook_url: webhook_url)

        # Enqueue processing
        ApiBatchProcessingJob.perform_later(batch_job.id)

        items_by_type = batch_job.batch_job_items.group(:input_type).count

        render_success({
          batch_id: batch_job.public_id,
          status: "processing",
          total_items: batch_job.total_items,
          items_by_type: items_by_type,
          estimated_seconds: batch_job.estimated_seconds_remaining,
          poll_url: "/api/v1/batch-jobs/#{batch_job.public_id}"
        }, status: :accepted)
      end

      private

      def format_search_result(result)
        {
          code: result[:code],
          description: result[:description],
          score: result[:score]
        }.compact
      end

      def format_commodity(commodity)
        {
          code: commodity[:code],
          description: commodity[:description],
          duty_rate: commodity[:duty_rate],
          notes: commodity[:notes]
        }.compact
      end

      def format_suggestion(result)
        {
          commodity_code: result[:commodity_code],
          confidence: result[:confidence],
          reasoning: result[:reasoning],
          category: result[:category],
          validated: result[:validated],
          official_description: result[:official_description],
          duty_rate: result[:duty_rate]
        }.tap do |response|
          response[:scraped_product] = result[:scraped_product] if result[:scraped_product].present?
        end.compact
      end

      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end

      def validate_batch_items(items)
        errors = []

        items.each_with_index do |item, index|
          if item[:description].blank? && item[:url].blank?
            errors << { index: index, error: "Item must have either 'description' or 'url'" }
          end

          if item[:url].present? && !valid_url?(item[:url])
            errors << { index: index, error: "Invalid URL format" }
          end
        end

        errors
      end

      def create_single_item_batch(url:, webhook_url:)
        batch_job = current_api_key.batch_jobs.create!(
          total_items: 1,
          webhook_url: webhook_url
        )

        batch_job.batch_job_items.create!(
          input_type: :url,
          url: url
        )

        batch_job
      end

      def create_batch_job(items:, webhook_url:)
        batch_job = current_api_key.batch_jobs.create!(
          total_items: items.size,
          webhook_url: webhook_url
        )

        items.each do |item|
          if item[:url].present?
            batch_job.batch_job_items.create!(
              external_id: item[:id],
              input_type: :url,
              url: item[:url]
            )
          else
            batch_job.batch_job_items.create!(
              external_id: item[:id],
              input_type: :description,
              description: item[:description]
            )
          end
        end

        batch_job
      end
    end
  end
end
