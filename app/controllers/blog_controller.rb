class BlogController < ApplicationController
  def index
    @posts = BlogPostService.all
  end

  def show
    @post = BlogPostService.find_by_slug!(params[:slug])
  end
end
