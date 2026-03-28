ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "factory_bot_rails"
require "mocha/minitest"
require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri]
  }
  config.allow_http_connections_when_no_cassette = false
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    include FactoryBot::Syntax::Methods

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Wraps the block in a VCR cassette. The cassette file is stored at
    # test/vcr_cassettes/<name>.yml and is created automatically on first run.
    #
    # Usage:
    #   stub_http_requests("rightmove/listing_172607297") do
    #     RightmoveScraper.new.fetch_listing("172607297")
    #   end
    def stub_http_requests(cassette_name, **vcr_options, &block)
      VCR.use_cassette(cassette_name, **vcr_options, &block)
    end
  end
end
