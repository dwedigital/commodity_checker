class ProductLookupsController < ApplicationController
  before_action :authenticate_user!, except: [:new, :create, :quick_lookup]
  before_action :set_product_lookup, only: [:show, :confirm_commodity_code, :add_to_order]

  def index
    @product_lookups = current_user.product_lookups
                                   .includes(:order_item)
                                   .with_attached_product_image
                                   .order(created_at: :desc)
  end

  def new
    @product_lookup = ProductLookup.new
  end

  def create
    # Guest users get a quick lookup without saving
    unless user_signed_in?
      return quick_lookup
    end

    @product_lookup = current_user.product_lookups.build(product_lookup_params)
    @product_lookup.scrape_status = :pending

    if @product_lookup.save
      # Queue background scraping and suggestion
      ScrapeProductPageJob.perform_later(product_lookup_id: @product_lookup.id)

      redirect_to @product_lookup, notice: "Looking up product... This may take a moment."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def quick_lookup
    url = params.dig(:product_lookup, :url) || params[:url]

    if url.blank?
      @product_lookup = ProductLookup.new
      @product_lookup.errors.add(:url, "can't be blank")
      return render :new, status: :unprocessable_entity
    end

    # Scrape synchronously for guest users
    scraper = ProductScraperService.new
    @scrape_result = scraper.scrape(url)

    # Get commodity code suggestion if scraping succeeded
    if @scrape_result[:status] == :completed || @scrape_result[:status] == :partial
      description = [
        @scrape_result[:title],
        @scrape_result[:description],
        @scrape_result[:brand],
        @scrape_result[:category],
        @scrape_result[:material]
      ].compact.reject(&:blank?).join(". ")

      if description.present?
        suggester = LlmCommoditySuggester.new
        @suggestion = suggester.suggest(description)
      end
    end

    @product_lookup = ProductLookup.new(url: url)
    render :quick_result
  end

  def show
    # Reload to get latest scrape status
    @product_lookup.reload if @product_lookup.pending?
  end

  def confirm_commodity_code
    @product_lookup.update!(confirmed_commodity_code: params[:commodity_code])
    redirect_to @product_lookup, notice: "Commodity code confirmed."
  end

  def add_to_order
    @order = current_user.orders.find(params[:order_id])

    order_item = @order.order_items.create!(
      description: @product_lookup.display_description,
      product_url: @product_lookup.url,
      product_lookup: @product_lookup,
      suggested_commodity_code: @product_lookup.suggested_commodity_code,
      commodity_code_confidence: @product_lookup.commodity_code_confidence,
      llm_reasoning: @product_lookup.llm_reasoning
    )

    @product_lookup.update!(order_item: order_item)

    redirect_to @order, notice: "Product added to order."
  end

  def create_from_photo
    unless user_signed_in?
      redirect_to new_user_session_path, alert: "Please sign in to use photo lookup."
      return
    end

    @product_lookup = current_user.product_lookups.build(
      lookup_type: :photo,
      scrape_status: :pending
    )

    if params[:product_lookup]&.dig(:product_image).present?
      @product_lookup.product_image.attach(params[:product_lookup][:product_image])
    end

    if @product_lookup.save
      # Queue background image analysis
      AnalyzeProductImageJob.perform_later(@product_lookup.id)

      redirect_to @product_lookup, notice: "Analyzing product image... This may take a moment."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_product_lookup
    @product_lookup = current_user.product_lookups.find(params[:id])
  end

  def product_lookup_params
    params.require(:product_lookup).permit(:url)
  end
end
