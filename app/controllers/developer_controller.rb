class DeveloperController < ApplicationController
  before_action :authenticate_user!
  before_action :require_api_access, except: [ :index ]

  def index
    # Show upsell for free users, dashboard for subscribers
    unless current_user.has_api_access?
      render :upsell and return
    end

    @api_keys = current_user.api_keys.order(created_at: :desc)
    @active_keys = @api_keys.active

    # Filter by specific key if requested
    @selected_key_id = params[:key_id].presence&.to_i
    @selected_key = @api_keys.find_by(id: @selected_key_id) if @selected_key_id

    # Get all API key IDs for this user
    all_key_ids = @api_keys.pluck(:id)

    if all_key_ids.any?
      # Aggregate usage stats across all keys
      @usage_stats = {
        requests_today: @active_keys.sum(:requests_today),
        requests_this_month: @active_keys.sum(:requests_this_month),
        limit_today: @active_keys.first&.requests_per_day_limit,
        limit_per_minute: @active_keys.first&.requests_per_minute_limit,
        batch_size_limit: @active_keys.first&.batch_size_limit
      }

      # Recent requests - filter by key if selected, otherwise show all
      request_scope = ApiRequest.where(api_key_id: @selected_key ? @selected_key.id : all_key_ids)
      @recent_requests = request_scope.includes(:api_key)
                                      .order(created_at: :desc)
                                      .limit(20)
    end
  end

  def create_api_key
    @api_key = current_user.api_keys.build(
      name: params[:name].presence || "API Key",
      tier: current_user.subscription_tier
    )

    if @api_key.save
      flash[:api_key_created] = @api_key.raw_key
      redirect_to developer_path, notice: "API key created. Copy it now - it won't be shown again!"
    else
      redirect_to developer_path, alert: @api_key.errors.full_messages.join(", ")
    end
  end

  def revoke_api_key
    @api_key = current_user.api_keys.find(params[:id])
    @api_key.revoke!
    redirect_to developer_path, notice: "API key revoked."
  end

  private

  def require_api_access
    unless current_user.has_api_access?
      redirect_to developer_path, alert: "API access requires a Starter subscription or higher."
    end
  end
end
