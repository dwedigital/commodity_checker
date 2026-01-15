class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @orders = current_user.orders.includes(:order_items).order(created_at: :desc).limit(10)
    @pending_codes = current_user.orders.joins(:order_items)
                                 .where(order_items: { confirmed_commodity_code: nil })
                                 .where.not(order_items: { suggested_commodity_code: nil })
                                 .distinct.count
  end
end
