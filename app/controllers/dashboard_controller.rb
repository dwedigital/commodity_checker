class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = current_user.orders.includes(:order_items).order(created_at: :desc).limit(5)
    @total_orders = current_user.orders.count
    @in_transit = current_user.orders.where(status: :in_transit).count
    @total_lookups = current_user.product_lookups.count
    @recent_lookups = current_user.product_lookups.order(created_at: :desc).limit(5)
    @total_items = OrderItem.joins(:order).where(orders: { user_id: current_user.id }).count
  end
end
