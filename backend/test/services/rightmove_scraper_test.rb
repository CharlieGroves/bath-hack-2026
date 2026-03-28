require "test_helper"

class RightmoveScraperTest < ActiveSupport::TestCase
  setup do
    @scraper = RightmoveScraper.new
  end

  # ------------------------------------------------------------------
  # fetch_listing — each test has its own VCR cassette
  # ------------------------------------------------------------------

  test "fetch_listing returns a hash of property attributes" do
    stub_http_requests("rightmove_scraper/fetch_listing_returns_a_hash") do
      assert_instance_of Hash, @scraper.fetch_listing("172607297")
    end
  end

  test "fetch_listing sets rightmove_id" do
    stub_http_requests("rightmove_scraper/fetch_listing_sets_rightmove_id") do
      assert_equal "172607297", @scraper.fetch_listing("172607297")[:rightmove_id]
    end
  end

  test "fetch_listing sets listing_url" do
    stub_http_requests("rightmove_scraper/fetch_listing_sets_listing_url") do
      assert_equal "https://www.rightmove.co.uk/properties/172607297",
                   @scraper.fetch_listing("172607297")[:listing_url]
    end
  end

  test "fetch_listing parses title" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_title") do
      assert_equal "3 bedroom terraced house for sale",
                   @scraper.fetch_listing("172607297")[:title]
    end
  end

  test "fetch_listing strips HTML from description" do
    stub_http_requests("rightmove_scraper/fetch_listing_strips_html_from_description") do
      assert_equal "A stunning zero-carbon home in the BedZED eco village.",
                   @scraper.fetch_listing("172607297")[:description]
    end
  end

  test "fetch_listing parses key_features as array" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_key_features") do
      features = @scraper.fetch_listing("172607297")[:key_features]
      assert_includes features, "Private garden"
      assert_includes features, "Vaulted ceilings with skylights"
    end
  end

  test "fetch_listing parses price into pence" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_price_into_pence") do
      assert_equal 45_000_000, @scraper.fetch_listing("172607297")[:price_pence]
    end
  end

  test "fetch_listing parses price_qualifier" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_price_qualifier") do
      assert_equal "Guide Price", @scraper.fetch_listing("172607297")[:price_qualifier]
    end
  end

  test "fetch_listing parses bedrooms and bathrooms" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_bedrooms_and_bathrooms") do
      result = @scraper.fetch_listing("172607297")
      assert_equal 3, result[:bedrooms]
      assert_equal 2, result[:bathrooms]
    end
  end

  test "fetch_listing parses size in sqft" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_size_in_sqft") do
      assert_equal 979, @scraper.fetch_listing("172607297")[:size_sqft]
    end
  end

  test "fetch_listing normalises property_type" do
    stub_http_requests("rightmove_scraper/fetch_listing_normalises_property_type") do
      assert_equal "terraced", @scraper.fetch_listing("172607297")[:property_type]
    end
  end

  test "fetch_listing normalises tenure" do
    stub_http_requests("rightmove_scraper/fetch_listing_normalises_tenure") do
      assert_equal "leasehold", @scraper.fetch_listing("172607297")[:tenure]
    end
  end

  test "fetch_listing parses lease_years_remaining" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_lease_years_remaining") do
      assert_equal 975, @scraper.fetch_listing("172607297")[:lease_years_remaining]
    end
  end

  test "fetch_listing parses epc_rating" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_epc_rating") do
      assert_equal "A", @scraper.fetch_listing("172607297")[:epc_rating]
    end
  end

  test "fetch_listing parses council_tax_band" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_council_tax_band") do
      assert_equal "C", @scraper.fetch_listing("172607297")[:council_tax_band]
    end
  end

  test "fetch_listing parses service_charge_annual_pence" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_service_charge") do
      assert_equal 267_000, @scraper.fetch_listing("172607297")[:service_charge_annual_pence]
    end
  end

  test "fetch_listing parses address fields" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_address_fields") do
      result = @scraper.fetch_listing("172607297")
      assert_equal "Dunster Way, Hackbridge, Wallington, SM6", result[:address_line_1]
      assert_equal "Wallington", result[:town]
      assert_equal "SM6", result[:postcode]
    end
  end

  test "fetch_listing parses latitude and longitude" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_lat_lng") do
      result = @scraper.fetch_listing("172607297")
      assert_in_delta 51.3812, result[:latitude], 0.0001
      assert_in_delta(-0.1534, result[:longitude], 0.0001)
    end
  end

  test "fetch_listing parses agent name and phone" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_agent") do
      result = @scraper.fetch_listing("172607297")
      assert_equal "Rosindale Pavitt, Wallington", result[:agent_name]
      assert_equal "020 3909 6696", result[:agent_phone]
    end
  end

  test "fetch_listing sets has_floor_plan true when floorplan present" do
    stub_http_requests("rightmove_scraper/fetch_listing_has_floor_plan") do
      assert @scraper.fetch_listing("172607297")[:has_floor_plan]
    end
  end

  test "fetch_listing sets has_virtual_tour true when tour present" do
    stub_http_requests("rightmove_scraper/fetch_listing_has_virtual_tour") do
      assert @scraper.fetch_listing("172607297")[:has_virtual_tour]
    end
  end

  test "fetch_listing parses photo_urls as array" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_photo_urls") do
      urls = @scraper.fetch_listing("172607297")[:photo_urls]
      assert_equal 2, urls.length
      assert urls.first.start_with?("https://")
    end
  end

  test "fetch_listing joins utilities into a string" do
    stub_http_requests("rightmove_scraper/fetch_listing_joins_utilities") do
      assert_equal "Electricity, Water, Sewerage",
                   @scraper.fetch_listing("172607297")[:utilities_text]
    end
  end

  test "fetch_listing defaults status to active when blank" do
    stub_http_requests("rightmove_scraper/fetch_listing_defaults_status") do
      assert_equal "active", @scraper.fetch_listing("172607297")[:status]
    end
  end

  test "fetch_listing parses listed_at date" do
    stub_http_requests("rightmove_scraper/fetch_listing_parses_listed_at") do
      assert_equal Date.new(2026, 2, 26), @scraper.fetch_listing("172607297")[:listed_at]
    end
  end

  test "fetch_listing sets last_seen_at to now" do
    stub_http_requests("rightmove_scraper/fetch_listing_sets_last_seen_at") do
      freeze_time do
        assert_in_delta Time.current.to_i,
                        @scraper.fetch_listing("172607297")[:last_seen_at].to_i, 1
      end
    end
  end

  test "fetch_listing stores raw_data" do
    stub_http_requests("rightmove_scraper/fetch_listing_stores_raw_data") do
      raw = @scraper.fetch_listing("172607297")[:raw_data]
      assert_instance_of Hash, raw
      assert raw.key?("propertyData")
    end
  end

  # ------------------------------------------------------------------
  # Error handling — inline stubs, no cassette needed
  # ------------------------------------------------------------------

  test "raises ScrapingError on non-200 response" do
    stub_request(:get, /rightmove\.co\.uk/)
      .to_return(status: 403, body: "Forbidden")

    assert_raises(RightmoveScraper::ScrapingError) do
      @scraper.fetch_listing("000000")
    end
  end

  test "raises ScrapingError when PAGE_MODEL is missing" do
    stub_request(:get, /rightmove\.co\.uk/)
      .to_return(status: 200, body: "<html><body><p>No data here</p></body></html>")

    assert_raises(RightmoveScraper::ScrapingError) do
      @scraper.fetch_listing("000000")
    end
  end

  test "raises ScrapingError on malformed JSON" do
    stub_request(:get, /rightmove\.co\.uk/)
      .to_return(
        status: 200,
        body: "<html><body><script>window.PAGE_MODEL = { invalid json ;</script></body></html>"
      )

    assert_raises(RightmoveScraper::ScrapingError) do
      @scraper.fetch_listing("000000")
    end
  end

  # ------------------------------------------------------------------
  # normalise_property_type
  # ------------------------------------------------------------------

  test "normalises flat variants" do
    assert_equal "flat", @scraper.__send__(:normalise_property_type, "apartment")
  end

  test "normalises semi-detached variants" do
    assert_equal "semi_detached", @scraper.__send__(:normalise_property_type, "Semi-Detached")
  end

  test "falls back to other for unknown types" do
    assert_equal "other", @scraper.__send__(:normalise_property_type, "castle")
  end

  # ------------------------------------------------------------------
  # normalise_tenure
  # ------------------------------------------------------------------

  test "normalises freehold" do
    assert_equal "freehold", @scraper.__send__(:normalise_tenure, "Freehold")
  end

  test "normalises share of freehold" do
    assert_equal "share_of_freehold", @scraper.__send__(:normalise_tenure, "Share of Freehold")
  end

  test "returns nil for unknown tenure" do
    assert_nil @scraper.__send__(:normalise_tenure, "")
  end

  # ------------------------------------------------------------------
  # normalise_status
  # ------------------------------------------------------------------

  test "normalises under offer" do
    assert_equal "under_offer", @scraper.__send__(:normalise_status, "Under Offer")
  end

  test "normalises SSTC" do
    assert_equal "under_offer", @scraper.__send__(:normalise_status, "SSTC")
  end

  test "normalises sold" do
    assert_equal "sold", @scraper.__send__(:normalise_status, "Sold")
  end

  test "defaults to active" do
    assert_equal "active", @scraper.__send__(:normalise_status, "")
  end

  # ------------------------------------------------------------------
  # parse_price
  # ------------------------------------------------------------------

  test "parses price string to pence" do
    assert_equal 45_000_000, @scraper.__send__(:parse_price, "£450,000")
  end

  test "returns nil for blank price" do
    assert_nil @scraper.__send__(:parse_price, "")
    assert_nil @scraper.__send__(:parse_price, nil)
  end

  # ------------------------------------------------------------------
  # parse_date
  # ------------------------------------------------------------------

  test "parses date string" do
    assert_equal Date.new(2026, 2, 26), @scraper.__send__(:parse_date, "26/02/2026")
  end

  test "strips Added on prefix" do
    assert_equal Date.new(2026, 2, 26), @scraper.__send__(:parse_date, "Added on 26/02/2026")
  end

  test "returns nil for blank date" do
    assert_nil @scraper.__send__(:parse_date, nil)
  end
end
