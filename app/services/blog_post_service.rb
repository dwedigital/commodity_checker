class BlogPostService
  CONTENT_DIR = Rails.root.join("content", "blog")

  BlogPost = Struct.new(
    :title,
    :slug,
    :date,
    :description,
    :hero_image,
    :author,
    :published,
    :tags,
    :content,
    :rendered_content,
    keyword_init: true
  )

  class << self
    def all
      posts = Dir.glob(CONTENT_DIR.join("*.md")).filter_map do |file_path|
        parse_file(file_path)
      end

      posts = posts.select(&:published) if Rails.env.production?
      posts.sort_by { |post| post.date }.reverse
    end

    def find_by_slug(slug)
      all.find { |post| post.slug == slug }
    end

    def find_by_slug!(slug)
      find_by_slug(slug) || raise(ActiveRecord::RecordNotFound, "Blog post not found: #{slug}")
    end

    private

    def parse_file(file_path)
      content = File.read(file_path)

      # Split front matter from content
      if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
        front_matter = YAML.safe_load($1, permitted_classes: [ Date, Time ])
        markdown_content = $2

        BlogPost.new(
          title: front_matter["title"],
          slug: front_matter["slug"] || File.basename(file_path, ".md"),
          date: parse_date(front_matter["date"]),
          description: front_matter["description"],
          hero_image: front_matter["hero_image"],
          author: front_matter["author"] || "Tariffik Team",
          published: front_matter.fetch("published", true),
          tags: front_matter["tags"] || [],
          content: markdown_content,
          rendered_content: render_markdown(markdown_content)
        )
      else
        Rails.logger.warn "Blog post missing front matter: #{file_path}"
        nil
      end
    rescue => e
      Rails.logger.error "Error parsing blog post #{file_path}: #{e.message}"
      nil
    end

    def parse_date(date)
      case date
      when Date
        date
      when Time
        date.to_date
      when String
        Date.parse(date)
      else
        Date.today
      end
    end

    def render_markdown(content)
      renderer = RougeRenderer.new(
        hard_wrap: true,
        link_attributes: { target: "_blank", rel: "noopener noreferrer" }
      )

      markdown = Redcarpet::Markdown.new(
        renderer,
        autolink: true,
        tables: true,
        fenced_code_blocks: true,
        strikethrough: true,
        superscript: true,
        footnotes: true,
        highlight: true
      )

      markdown.render(content).html_safe
    end
  end

  class RougeRenderer < Redcarpet::Render::HTML
    def block_code(code, language)
      language ||= "text"
      lexer = Rouge::Lexer.find_fancy(language, code) || Rouge::Lexers::PlainText.new
      formatter = Rouge::Formatters::HTMLLegacy.new(css_class: "highlight")

      <<~HTML
        <div class="code-block">
          <pre class="#{language}">#{formatter.format(lexer.lex(code))}</pre>
        </div>
      HTML
    end
  end
end
