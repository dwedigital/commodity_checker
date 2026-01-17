xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  # Static pages
  @static_pages.each do |page|
    xml.url do
      xml.loc page[:path]
      xml.changefreq page[:changefreq]
      xml.priority page[:priority]
    end
  end

  # Blog posts
  @blog_posts.each do |post|
    xml.url do
      xml.loc blog_post_url(post.slug)
      xml.lastmod post.date.to_time.iso8601
      xml.changefreq "monthly"
      xml.priority "0.7"
    end
  end
end
