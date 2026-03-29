namespace :ml do
  desc "Export the current property dataset for local ML training"
  task export_dataset: :environment do
    output_path = Pathname.new(ENV.fetch("OUTPUT", Rails.root.join("..", "ml-training", "data", "properties.json").to_s))
    output_path.dirname.mkpath

    include_map = {
      property_transport_snapshot: "property_transport_snapshots",
      property_crime_snapshot: "property_crime_snapshots",
      property_nearest_stations: "property_nearest_stations",
      air_quality_station: "air_quality_stations",
      area_price_growth: "area_price_growths",
      borough: "boroughs",
      estate_agent: "estate_agents"
    }
    available_includes = include_map.filter_map do |association, table_name|
      association if ActiveRecord::Base.connection.data_source_exists?(table_name)
    rescue StandardError
      nil
    end

    properties = Property.includes(*available_includes).order(:id)

    payload = {
      generated_at: Time.current.iso8601,
      property_count: properties.count,
      properties: properties.map { |property| PropertyMachineLearningPayloadBuilder.new(property).as_json }
    }

    output_path.write(JSON.pretty_generate(payload))
    puts "Exported #{payload[:property_count]} properties to #{output_path}"
  end
end
