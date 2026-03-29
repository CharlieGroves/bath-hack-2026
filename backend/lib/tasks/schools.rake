namespace :schools do
  desc <<~DESC
    Import schools from data/london_schools_ks4.csv into the schools table.

    Optional:
      CSV_PATH - Path to the CSV file (default: data/london_schools_ks4.csv)
  DESC
  task import: :environment do
    csv_path = ENV.fetch("CSV_PATH", SchoolImporter::DEFAULT_PATH)
    count = SchoolImporter.new(csv_path: csv_path).call
    puts "Imported #{count} schools."
  end

  desc <<~DESC
    Geocode schools that are missing latitude/longitude via Nominatim (postcode lookup).

    Nominatim enforces a 1 req/s rate limit; this task sleeps between requests.

    Optional:
      BATCH_SIZE - Number of schools to geocode per run (default: all)
  DESC
  task geocode: :environment do
    scope = School.not_geocoded.order(:id)
    scope = scope.limit(ENV["BATCH_SIZE"].to_i) if ENV["BATCH_SIZE"].present?

    total   = scope.count
    success = 0
    failed  = 0

    if total.zero?
      puts "All schools are already geocoded."
      next
    end

    geocoder = NominatimGeocoder.new
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    scope.find_each do |school|
      result = geocoder.search!(school.postcode)
      school.update_columns(latitude: result[:latitude], longitude: result[:longitude])
      success += 1
    rescue NominatimGeocoder::Error => e
      warn "  WARN urn=#{school.urn} postcode=#{school.postcode} error=#{e.message}"
      failed += 1
    ensure
      sleep 1.1
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    puts "Geocoded #{success}/#{total} schools in #{elapsed.round(1)}s. Failed: #{failed}."
  end
end
