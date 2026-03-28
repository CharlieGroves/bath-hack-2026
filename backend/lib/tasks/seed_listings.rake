namespace :seed do
  desc <<~DESC
    Seed the database with Rightmove listings scraped from a search URL.

    Required:
      URL   - Rightmove search URL (copy directly from browser)

    Optional:
      LIMIT - Maximum number of listings to scrape (default: 100)
      DELAY - Seconds to sleep between individual listing requests (default: 1)

    Example:
      bundle exec rails seed:listings \\
        URL="https://www.rightmove.co.uk/property-for-sale/find.html?..." \\
        LIMIT=50 \\
        DELAY=2
  DESC
  task listings: :environment do
    default_url = "https://www.rightmove.co.uk/property-for-sale/find.html?propertyTypes=terraced%2Csemi-detached&dontShow=newHome%2Cretirement%2CsharedOwnership%2Cauction&channel=BUY&index=0&newHome=false&retirement=false&auction=false&partBuyPartRent=false&sortType=2&areaSizeUnit=sqft&maxPrice=450000&locationIdentifier=USERDEFINEDAREA%5E%7B%22polylines%22%3A%22ia_yHb%7Dg%40%7EFgb%5CcrDw%7E_%40vYc%7EExy%40guChoBor%40%7EaB%3FbmE%60dCvdBlT%7EdCniI%60hEtaB%60GvyPu%7C%40paXuAhmGdg%40%60dCjD%60bDmTrlCajAxtAkxGzrB%7BwEnT%7DyAqpAiwA%7BgL%60O%60%5D%22%7D&transactionType=BUY&displayLocationIdentifier=undefined"
    url   = ENV.fetch("URL", default_url)
    limit = ENV.fetch("LIMIT", "100").to_i
    delay = ENV.fetch("DELAY", "1").to_f

    puts "Collecting up to #{limit} property IDs from search results..."

    search_scraper = RightmoveSearchScraper.new
    ids = search_scraper.property_ids(url, limit: limit)

    puts "Found #{ids.length} property IDs. Scraping listings...\n\n"

    scraper   = RightmoveScraper.new
    new_count = 0
    updated_count = 0
    error_count   = 0

    ids.each_with_index do |rightmove_id, i|
      print "[#{i + 1}/#{ids.length}] #{rightmove_id} ... "

      begin
        attrs    = scraper.fetch_listing(rightmove_id)
        property = Property.find_or_initialize_by(rightmove_id: rightmove_id)
        is_new   = property.new_record?
        property.assign_attributes(attrs)
        property.save!

        if is_new
          new_count += 1
          puts "created (#{property.address_line_1})"
        else
          updated_count += 1
          puts "updated"
        end
      rescue RightmoveScraper::ScrapingError => e
        error_count += 1
        puts "ERROR: #{e.message}"
      rescue ActiveRecord::RecordInvalid => e
        error_count += 1
        puts "DB ERROR: #{e.message}"
      end

      sleep delay unless i == ids.length - 1
    end

    puts "\nDone. Created: #{new_count}  Updated: #{updated_count}  Errors: #{error_count}"
  end
end
