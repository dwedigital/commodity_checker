class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = current_user.orders.includes(:order_items).order(created_at: :desc).limit(10)
    @total_items = OrderItem.joins(:order).where(orders: { user_id: current_user.id }).count
  end
end
