namespace :import do
  desc "Import London area growth data and link matching properties"
  task area_price_growths: :environment do
    csv_path = ENV.fetch("CSV_PATH", Rails.root.join("data", "london_area_house_growth_per_year.csv").to_s)

    AreaPriceGrowthImporter.new(csv_path: csv_path).call

    puts "Imported #{AreaPriceGrowth.count} London area growth records"
    puts "Linked #{Property.where.not(area_price_growth_id: nil).count} properties to area growth records"
  end
end

namespace :auto_import do
  task area_price_growths: :environment do
    next if ENV["DISABLE_AUTO_AREA_PRICE_GROWTH_IMPORT"] == "1"

    csv_path = Rails.root.join("data", "london_area_house_growth_per_year.csv")
    next unless csv_path.exist?
    next unless ActiveRecord::Base.connection.data_source_exists?("area_price_growths")

    AreaPriceGrowthImporter.new(csv_path: csv_path).call

    puts "Auto-imported London area growth data"
  end
end

Rake::Task["db:migrate"].enhance(["auto_import:area_price_growths"])
Rake::Task["db:prepare"].enhance(["auto_import:area_price_growths"])
