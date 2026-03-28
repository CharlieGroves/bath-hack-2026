require "faraday"
require "nokogiri"
require "json"

# Fetches and parses a Rightmove property listing page.
#
# Rightmove embeds all listing data as JSON inside a <script> tag —
# no JavaScript rendering is required.
#
# Usage:
#   scraper = RightmoveScraper.new
#   attrs   = scraper.fetch_listing("172607297")
#   Property.find_or_initialize_by(rightmove_id: attrs[:rightmove_id])
#           .update!(attrs)
class RightmoveScraper
  BASE_URL     = "https://www.rightmove.co.uk"
  LISTING_PATH = "/properties/%s"

  # Raised when the page cannot be fetched or parsed.
  class ScrapingError < StandardError; end

  def fetch_listing(rightmove_id)
    url  = BASE_URL + LISTING_PATH % rightmove_id
    html = fetch_html(url)
    data = extract_json_payload(html)
    parse_listing(data, rightmove_id, url)
  end

  private

  # ------------------------------------------------------------------
  # HTTP
  # ------------------------------------------------------------------

  def fetch_html(url)
    conn = Faraday.new do |f|
      f.headers["User-Agent"]      = "Mozilla/5.0 (compatible; Bath-Hack-Bot/1.0)"
      f.headers["Accept"]          = "text/html,application/xhtml+xml"
      f.headers["Accept-Language"] = "en-GB,en;q=0.9"
    end

    response = conn.get(url)
    raise ScrapingError, "HTTP #{response.status} for #{url}" unless response.success?

    response.body
  end

  # ------------------------------------------------------------------
  # JSON extraction
  # ------------------------------------------------------------------

  # Rightmove embeds listing data in a <script> block as:
  #   window.PAGE_MODEL = { ... }
  # We locate that block and parse the JSON object.
  def extract_json_payload(html)
    doc    = Nokogiri::HTML(html)
    script = doc.css("script").find { |s| s.text.include?("PAGE_MODEL") }

    raise ScrapingError, "Could not find PAGE_MODEL in page" unless script

    json_str = script.text.match(/window\.PAGE_MODEL\s*=\s*(\{.+\})\s*;?\s*$/m)&.captures&.first
    raise ScrapingError, "Could not extract PAGE_MODEL JSON" unless json_str

    JSON.parse(json_str)
  rescue JSON::ParserError => e
    raise ScrapingError, "JSON parse error: #{e.message}"
  end

  # ------------------------------------------------------------------
  # Parsing
  # ------------------------------------------------------------------

  def parse_listing(data, rightmove_id, url)
    prop = data.dig("propertyData") || {}

    {
      rightmove_id:               rightmove_id.to_s,
      listing_url:                url,

      # Content
      title:                      prop.dig("text", "pageTitle"),
      description:                clean_html(prop.dig("text", "description")),
      key_features:               Array(prop.dig("keyFeatures")),
      photo_urls:                 extract_photo_urls(prop),

      # Price
      price_pence:                parse_price(prop.dig("prices", "primaryPrice")),
      price_qualifier:            prop.dig("prices", "priceQualifier"),
      price_per_sqft_pence:       parse_price(prop.dig("prices", "pricePerSqFt")),

      # Attributes
      property_type:              normalise_property_type(prop.dig("propertySubType") || prop.dig("propertyType")),
      bedrooms:                   prop.dig("bedrooms")&.to_i,
      bathrooms:                  prop.dig("bathrooms")&.to_i,
      size_sqft:                  parse_size_sqft(prop.dig("sizings")),

      # Tenure
      tenure:                     normalise_tenure(prop.dig("tenure", "tenureType")),
      lease_years_remaining:      prop.dig("tenure", "yearsRemainingOnLease")&.to_i,

      # Running costs
      epc_rating:                 prop.dig("epcGraphs", 0, "rating"),
      council_tax_band:           prop.dig("councilTaxExempt") ? nil : prop.dig("councilTax", "band"),
      service_charge_annual_pence: parse_service_charge(prop.dig("livingCosts", "annualServiceCharge")),

      # Location
      address_line_1:             prop.dig("address", "displayAddress"),
      town:                       prop.dig("address", "town"),
      postcode:                   prop.dig("address", "outcode"),
      latitude:                   prop.dig("location", "latitude"),
      longitude:                  prop.dig("location", "longitude"),

      # Agent
      agent_name:                 prop.dig("customer", "branchDisplayName"),
      agent_phone:                prop.dig("customer", "contactTelephone"),

      # Media
      has_floor_plan:             prop.dig("floorplans", 0).present?,
      has_virtual_tour:           prop.dig("virtualTours", 0).present?,

      # Free-text
      utilities_text:             extract_utilities(prop),
      parking_text:               prop.dig("parking"),

      # Lifecycle
      status:                     normalise_status(prop.dig("status")),
      listed_at:                  parse_date(prop.dig("listingUpdate", "listingUpdateDate") || prop.dig("addedOrReduced")),
      last_seen_at:               Time.current,

      raw_data:                   data
    }
  end

  # ------------------------------------------------------------------
  # Field helpers
  # ------------------------------------------------------------------

  def parse_price(str)
    return nil if str.blank?
    pence = str.to_s.gsub(/[^0-9]/, "").to_i
    pence > 0 ? pence * 100 : nil
  end

  def parse_size_sqft(sizings)
    return nil unless sizings.is_a?(Array)
    entry = sizings.find { |s| s["unit"] == "sqft" } || sizings.first
    entry&.dig("minimumSize")&.to_i
  end

  def parse_service_charge(val)
    return nil if val.blank?
    val.to_s.gsub(/[^0-9]/, "").to_i * 100
  end

  def parse_date(str)
    return nil if str.blank?
    Date.parse(str.to_s.gsub(/Added on |Reduced on /i, ""))
  rescue ArgumentError
    nil
  end

  def extract_photo_urls(prop)
    Array(prop.dig("images")).map { |img| img["url"] || img["srcUrl"] }.compact
  end

  def extract_utilities(prop)
    items = Array(prop.dig("utilities")).map { |u| u["description"] }.compact
    items.presence&.join(", ")
  end

  def clean_html(html)
    return nil if html.blank?
    Nokogiri::HTML.fragment(html).text.strip
  end

  def normalise_property_type(raw)
    map = {
      "flat"              => "flat",
      "apartment"         => "flat",
      "maisonette"        => "flat",
      "terraced"          => "terraced",
      "terraced house"    => "terraced",
      "semi-detached"     => "semi_detached",
      "semi detached"     => "semi_detached",
      "detached"          => "detached",
      "detached house"    => "detached",
      "bungalow"          => "bungalow",
      "land"              => "land"
    }
    map[raw.to_s.downcase.strip] || "other"
  end

  def normalise_tenure(raw)
    case raw.to_s.downcase
    when /leasehold/        then "leasehold"
    when /share.*freehold/  then "share_of_freehold"
    when /freehold/         then "freehold"
    end
  end

  def normalise_status(raw)
    case raw.to_s.downcase
    when /under.offer/, /sstc/ then "under_offer"
    when /sold/                then "sold"
    when /let/                 then "let"
    else                            "active"
    end
  end
end
