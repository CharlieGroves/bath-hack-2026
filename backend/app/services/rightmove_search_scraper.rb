require "faraday"
require "nokogiri"
require "json"
require "uri"

# Paginates a Rightmove search results URL and yields property IDs.
#
# Rightmove embeds all search data as JSON inside a <script> tag (window.PAGE_MODEL),
# so no JS rendering is required. Pagination uses the `index` query parameter,
# incrementing by PAGE_SIZE (24) each time.
#
# Usage:
#   scraper = RightmoveSearchScraper.new
#   ids = scraper.property_ids(url, limit: 50)
#   # => ["172607297", "143221054", ...]
class RightmoveSearchScraper
  PAGE_SIZE  = 25
  MAX_INDEX  = 1000 # Rightmove redirects beyond this

  class ScrapingError < StandardError; end

  # Returns up to `limit` property IDs from the search results for `url`.
  def property_ids(url, limit: 100)
    ids = []
    index = 0

    loop do
      page_ids, total = fetch_page(url, index)
      ids.concat(page_ids)

      puts "  Page #{index / PAGE_SIZE + 1}: #{page_ids.length} IDs (#{ids.length}/#{[limit, total].min} total)"

      break if ids.length >= limit
      break if ids.length >= total
      break if page_ids.empty?

      index += PAGE_SIZE
      break if index > MAX_INDEX
    end

    ids.first(limit)
  end

  private

  def fetch_page(base_url, index)
    paged_url = set_index(base_url, index)
    html = fetch_html(paged_url)
    data = extract_json_payload(html, paged_url)

    search_results = data.dig("props", "pageProps", "searchResults") || {}
    properties     = search_results["properties"] || []
    total          = search_results["resultCount"].to_s.gsub(/[^0-9]/, "").to_i
    total          = properties.length if total.zero?

    ids = properties.map { |p| p["id"].to_s }.reject(&:empty?)
    [ids, total]
  end

  def set_index(url, index)
    uri    = URI.parse(url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["index"] = index.to_s
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def fetch_html(url)
    conn = Faraday.new do |f|
      f.headers["User-Agent"]      = "Mozilla/5.0 (compatible; Bath-Hack-Bot/1.0)"
      f.headers["Accept"]          = "text/html,application/xhtml+xml"
      f.headers["Accept-Language"] = "en-GB,en;q=0.9"
      f.response :follow_redirects
    end

    response = conn.get(url)
    raise ScrapingError, "HTTP #{response.status} for #{url}" unless response.success?

    response.body
  end

  def extract_json_payload(html, url)
    doc    = Nokogiri::HTML(html)
    script = doc.at_css('script#__NEXT_DATA__')
    raise ScrapingError, "Could not find __NEXT_DATA__ in page: #{url}" unless script

    JSON.parse(script.text)
  rescue JSON::ParserError => e
    raise ScrapingError, "JSON parse error on #{url}: #{e.message}"
  end
end
