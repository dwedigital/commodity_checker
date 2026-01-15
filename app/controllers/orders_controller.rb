class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order, only: [ :show, :confirm_commodity_code, :refresh_tracking ]

  def index
    @orders = current_user.orders.includes(:order_items).order(created_at: :desc)
  end

  def show
  end

  def new
    @order = current_user.orders.build
  end

  def create
    @order = current_user.orders.build(order_params)

    if @order.save
      # Create order items from the items parameter
      items = params[:items]&.reject(&:blank?) || []
      items.each do |item_description|
        @order.order_items.create!(description: item_description, quantity: 1)
      end

      # If no items provided, create a placeholder
      if @order.order_items.empty?
        @order.order_items.create!(
          description: "Item from #{@order.retailer_name || 'order'}",
          quantity: 1
        )
      end

      # Queue commodity code suggestion
      SuggestCommodityCodesJob.perform_later(@order.id)

      redirect_to @order, notice: "Order created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def confirm_commodity_code
    @order_item = @order.order_items.find(params[:order_item_id])
    @order_item.update!(confirmed_commodity_code: params[:commodity_code])

    redirect_to @order, notice: "Commodity code confirmed."
  end

  def refresh_tracking
    UpdateTrackingJob.perform_now(@order.id)
    redirect_to @order, notice: "Tracking updated."
  rescue => e
    redirect_to @order, alert: "Failed to refresh tracking: #{e.message}"
  end

  def export
    @orders = current_user.orders.includes(:order_items)
                          .joins(:order_items)
                          .where.not(order_items: { confirmed_commodity_code: nil })
                          .distinct

    respond_to do |format|
      format.csv do
        headers["Content-Disposition"] = "attachment; filename=\"commodity_codes_#{Date.current}.csv\""
        headers["Content-Type"] = "text/csv"
      end
    end
  end

  private

  def set_order
    @order = current_user.orders.includes(:order_items, :tracking_events).find(params[:id])
  end

  def order_params
    params.require(:order).permit(:retailer_name, :order_reference, :estimated_delivery, :status)
  end
end
