require "csv"

class AreaPriceGrowthImporter
  DEFAULT_PATH = Rails.root.join("data", "london_area_house_growth_per_year.csv")

  AREA_ALIASES = {
    "BARKING" => "BARKING_AND_DAGENHAM",
    "DAGENHAM" => "BARKING_AND_DAGENHAM",
    "HAMMERSMITH" => "HAMMERSMITH_AND_FULHAM",
    "FULHAM" => "HAMMERSMITH_AND_FULHAM",
    "KENSINGTON" => "KENSINGTON_AND_CHELSEA",
    "CHELSEA" => "KENSINGTON_AND_CHELSEA",
    "RICHMOND" => "RICHMOND_UPON_THAMES",
    "KINGSTON" => "KINGSTON_UPON_THAMES",
    "CITY_OF_LONDON" => "CITY_OF_LONDON",
    "CITY OF LONDON" => "CITY_OF_LONDON",
    "WESTMINSTER" => "WESTMINSTER",
    "ISLINGTON" => "ISLINGTON",
    "CAMDEN" => "CAMDEN",
    "CROYDON" => "CROYDON",
    "ENFIELD" => "ENFIELD",
    "NEWHAM" => "NEWHAM",
    "WANDSWORTH" => "WANDSWORTH",
    "SOUTHWARK" => "SOUTHWARK",
    "LAMBETH" => "LAMBETH",
    "HOUNSLOW" => "HOUNSLOW",
    "HARINGEY" => "HARINGEY",
    "EALING" => "EALING",
    "BARNET" => "BARNET",
    "BRENT" => "BRENT",
    "BROMLEY" => "BROMLEY",
    "GREENWICH" => "GREENWICH",
    "HACKNEY" => "HACKNEY",
    "HARROW" => "HARROW",
    "HAVERING" => "HAVERING",
    "HILLINGDON" => "HILLINGDON",
    "LEWISHAM" => "LEWISHAM",
    "MERTON" => "MERTON",
    "REDBRIDGE" => "REDBRIDGE",
    "SUTTON" => "SUTTON",
    "TOWER_HAMLETS" => "TOWER_HAMLETS",
    "TOWER HAMLETS" => "TOWER_HAMLETS",
    "WALTHAM_FOREST" => "WALTHAM_FOREST",
    "WALTHAM FOREST" => "WALTHAM_FOREST"
  }.freeze

  def initialize(csv_path: DEFAULT_PATH)
    @csv_path = Pathname.new(csv_path)
  end

  def call
    ActiveRecord::Base.transaction do
      import_area_growths!
      assign_properties!
    end
  end

  private

  def import_area_growths!
    rows = grouped_rows.map do |area_slug, payload|
      {
        area_slug: area_slug,
        area_name: payload.fetch(:area_name),
        yearly_growth_data: payload.fetch(:yearly_growth_data),
        updated_at: Time.current,
        created_at: Time.current
      }
    end

    AreaPriceGrowth.upsert_all(rows, unique_by: :index_area_price_growths_on_area_slug)
  end

  def assign_properties!
    areas_by_slug = AreaPriceGrowth.all.index_by(&:area_slug)

    Property.find_each do |property|
      matched_slug = matched_area_slug(property, areas_by_slug.keys)
      next unless matched_slug

      property.update_columns(area_price_growth_id: areas_by_slug.fetch(matched_slug).id)
    end
  end

  def grouped_rows
    grouped = {}

    CSV.foreach(@csv_path, headers: true) do |row|
      area_slug = normalize_slug(row.fetch("area_slug"))
      grouped[area_slug] ||= {
        area_name: row.fetch("area_name"),
        yearly_growth_data: {}
      }

      grouped[area_slug][:yearly_growth_data][row.fetch("resale_year")] = {
        "average_change_pct_per_year" => row.fetch("average_change_pct_per_year").to_f,
        "stddev_change_pct_per_year" => row.fetch("stddev_change_pct_per_year").to_f,
        "sale_pairs_count" => row.fetch("sale_pairs_count").to_i
      }
    end

    grouped
  end

  def matched_area_slug(property, known_area_slugs)
    normalized_values(property).each do |value|
      alias_slug = AREA_ALIASES[value]
      return alias_slug if alias_slug && known_area_slugs.include?(alias_slug)

      return value if known_area_slugs.include?(value)
    end

    searchable_text(property).each do |text|
      known_area_slugs.each do |area_slug|
        return area_slug if text.include?(area_slug.tr("_", " "))
      end
    end

    nil
  end

  def normalized_values(property)
    [
      property.town,
      property.postcode,
      property.raw_data&.dig("propertyData", "address", "town"),
      property.raw_data&.dig("propertyData", "address", "outcode")
    ].compact.map { |value| normalize_slug(value) }.uniq
  end

  def searchable_text(property)
    [
      property.address_line_1,
      property.town,
      property.raw_data&.dig("propertyData", "address", "displayAddress")
    ].compact.map { |value| normalize_text(value) }.uniq
  end

  def normalize_slug(value)
    normalize_text(value).tr(" ", "_")
  end

  def normalize_text(value)
    value.to_s.upcase.gsub(/[^A-Z0-9 ]+/, " ").squeeze(" ").strip
  end
end
