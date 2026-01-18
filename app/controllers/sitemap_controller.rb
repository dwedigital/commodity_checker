class SitemapController < ApplicationController
  def index
    @static_pages = [
      { path: root_url, priority: "1.0", changefreq: "weekly" },
      { path: blog_url, priority: "0.8", changefreq: "weekly" },
      { path: privacy_url, priority: "0.3", changefreq: "yearly" },
      { path: terms_url, priority: "0.3", changefreq: "yearly" }
    ]

    @blog_posts = BlogPostService.all

    respond_to do |format|
      format.xml
    end
  end
end
