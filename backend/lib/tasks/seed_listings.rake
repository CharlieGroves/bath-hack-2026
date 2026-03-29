namespace :seed do
  desc <<~DESC
    Seed the database with Rightmove listings scraped from a search URL.
    Automatically batches by price band to work around Rightmove's ~1000 result cap.

    Required:
      URL   - Rightmove search URL (copy directly from browser)

    Optional:
      DELAY      - Seconds to wait between scrape jobs (default: 1)
      BAND_SIZE  - Price band width in £ (default: 50000)
      MIN_PRICE  - Starting price in £ (default: 0)
      MAX_PRICE  - Ending price in £ (default: 2000000)

    Example:
      bundle exec rails seed:listings \\
        URL="https://www.rightmove.co.uk/property-for-sale/find.html?..." \\
        BAND_SIZE=25000
  DESC
  task listings: :environment do
    default_url = "https://www.rightmove.co.uk/property-for-sale/find.html?dontShow=newHome%2Cretirement%2CsharedOwnership%2Cauction&channel=BUY&newHome=false&retirement=false&auction=false&partBuyPartRent=false&sortType=6&areaSizeUnit=sqft&locationIdentifier=REGION%5E87490&transactionType=BUY&displayLocationIdentifier=London-87490.html"
    url        = ENV.fetch("URL", default_url)
    delay      = ENV.fetch("DELAY", "1").to_f
    band_size  = ENV.fetch("BAND_SIZE", "50000").to_i
    min_price  = ENV.fetch("MIN_PRICE", "0").to_i
    max_price  = ENV.fetch("MAX_PRICE", "2000000").to_i

    bands = (min_price...max_price).step(band_size).map do |low|
      [low, low + band_size]
    end

    puts "Scraping #{bands.length} price bands (£#{min_price.then { |n| ActiveSupport::NumberHelper.number_to_delimited(n) }}–£#{max_price.then { |n| ActiveSupport::NumberHelper.number_to_delimited(n) }} in £#{band_size.then { |n| ActiveSupport::NumberHelper.number_to_delimited(n) }} steps)...\n\n"

    search_scraper = RightmoveSearchScraper.new
    all_ids = []

    bands.each_with_index do |(low, high), i|
      band_url = set_price_params(url, low, high)
      puts "[Band #{i + 1}/#{bands.length}] £#{low.then { |n| ActiveSupport::NumberHelper.number_to_delimited(n) }}–£#{high.then { |n| ActiveSupport::NumberHelper.number_to_delimited(n) }}"

      begin
        ids = search_scraper.property_ids(band_url)
        puts "  → #{ids.length} IDs collected"
        all_ids.concat(ids)
      rescue RightmoveSearchScraper::ScrapingError => e
        puts "  → ERROR: #{e.message} (skipping band)"
      end
    end

    all_ids.uniq!
    puts "\nFound #{all_ids.length} unique property IDs across all bands. Enqueuing scrape jobs...\n\n"

    all_ids.each_with_index do |rightmove_id, i|
      RightmoveScrapeJob.set(wait: i * delay).perform_later(rightmove_id)
      puts "[#{i + 1}/#{all_ids.length}] Enqueued #{rightmove_id}"
    end

    puts "\nDone. #{all_ids.length} jobs enqueued."
  end

  private

  def set_price_params(url, min, max)
    uri    = URI.parse(url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["minPrice"] = min.to_s
    params["maxPrice"] = max.to_s
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end
end
