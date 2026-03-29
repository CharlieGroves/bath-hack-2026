namespace :ml do
  desc "Export the current property dataset for local ML training"
  task export_dataset: :environment do
    output_path = Pathname.new(ENV.fetch("OUTPUT", Rails.root.join("..", "ml-training", "data", "properties.json").to_s))
    output_path.dirname.mkpath

    properties = Property
      .includes(:property_transport_snapshot, :property_crime_snapshot, :property_nearest_stations, :air_quality_station, :area_price_growth)
      .order(:id)

    payload = {
      generated_at: Time.current.iso8601,
      property_count: properties.count,
      properties: properties.map { |property| PropertyMachineLearningPayloadBuilder.new(property).as_json }
    }

    output_path.write(JSON.pretty_generate(payload))
    puts "Exported #{payload[:property_count]} properties to #{output_path}"
  end
end
