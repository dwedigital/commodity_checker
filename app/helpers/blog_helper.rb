module BlogHelper
  def blog_post_json_ld(post)
    data = {
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "headline" => post.title,
      "description" => post.description,
      "author" => {
        "@type" => "Person",
        "name" => post.author
      },
      "datePublished" => post.date.iso8601,
      "publisher" => {
        "@type" => "Organization",
        "name" => "Tariffik",
        "url" => root_url
      },
      "mainEntityOfPage" => {
        "@type" => "WebPage",
        "@id" => blog_post_url(post.slug)
      }
    }

    if post.hero_image.present?
      data["image"] = absolute_image_url(post.hero_image)
    end

    tag.script(data.to_json.html_safe, type: "application/ld+json")
  end

  def absolute_image_url(path)
    return path if path.start_with?("http")
    "#{request.base_url}#{path}"
  end

  def reading_time(content)
    words = content.split.size
    minutes = (words / 200.0).ceil
    "#{minutes} min read"
  end
end
