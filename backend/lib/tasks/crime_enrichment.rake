namespace :crime do
  desc "Enrich all properties with crime data, grouped by ~1km coordinate bucket (1 API call per bucket)"
  task enrich: :environment do
    TOLERANCE   = 0.005
    RATE_SLEEP  = 1.0 # seconds between bucket fetches

    buckets = Property
      .where.not(latitude: nil, longitude: nil)
      .pluck(:id, :latitude, :longitude)
      .group_by { |_, lat, lng| [(lat.to_f * 100).round, (lng.to_f * 100).round] }
      .transform_values { |rows| rows.map { |id, lat, lng| { id: id, lat: lat, lng: lng } } }

    # Skip buckets where all properties already have a ready snapshot
    pending_buckets = buckets.reject do |_, props|
      ids = props.map { |p| p[:id] }
      PropertyCrimeSnapshot.where(property_id: ids, status: "ready").count == ids.size
    end

    total   = pending_buckets.sum { |_, props| props.size }
    done    = 0
    skipped = 0

    puts "Buckets to fetch: #{pending_buckets.size} (covering #{total} properties)"
    puts "Estimated time:   ~#{pending_buckets.size} seconds"

    pending_buckets.each_with_index do |(_, props), i|
      anchor = props.first

      # Check if any property in this bucket already has a ready snapshot we can spread
      existing = PropertyCrimeSnapshot
        .joins(:property)
        .where(status: "ready")
        .where(
          "properties.latitude  BETWEEN ? AND ? AND properties.longitude BETWEEN ? AND ?",
          anchor[:lat].to_f - TOLERANCE, anchor[:lat].to_f + TOLERANCE,
          anchor[:lng].to_f - TOLERANCE, anchor[:lng].to_f + TOLERANCE
        )
        .order(fetched_at: :desc)
        .first

      if existing
        avg       = existing.avg_monthly_crimes
        fetched   = existing.fetched_at
        skipped  += 1
      else
        avg = CrimeRateGateway.average_crime_rate(
          lat:        anchor[:lat],
          lng:        anchor[:lng],
          crime_type: "all-crime",
          months:     3
        )
        fetched = Time.current
        sleep RATE_SLEEP
      end

      now = Time.current
      props.each do |p|
        property = Property.find(p[:id])
        snapshot = property.property_crime_snapshot || property.build_property_crime_snapshot
        next if snapshot.persisted? && snapshot.status == "ready"

        snapshot.update!(
          latitude:           p[:lat],
          longitude:          p[:lng],
          avg_monthly_crimes: avg,
          fetched_at:         fetched,
          status:             "ready",
          error_message:      nil
        )
        done += 1
      end

      if (i + 1) % 50 == 0
        pct = ((i + 1).to_f / pending_buckets.size * 100).round
        puts "  #{i + 1}/#{pending_buckets.size} buckets (#{pct}%) — #{done} properties enriched"
      end
    rescue CrimeRate::RequestError => e
      puts "  WARN bucket #{i + 1} failed: #{e.message} — skipping"
    end

    puts "Done. #{done} properties enriched, #{skipped} buckets served from cache."
  end
end
