export interface NearestStation {
  name: string
  distance_miles: number
  walking_minutes: number
  transport_type: string
}

export interface NoiseSection {
  covered: boolean
  easting?: number
  northing?: number
  metrics: Record<string, number | null>
}

export interface PropertyNoise {
  provider: string
  status: string
  fetched_at: string | null
  flight_data: NoiseSection
  rail_data: NoiseSection
  road_data: NoiseSection
}

export interface PropertyCrime {
  status: string
  avg_monthly_crimes: number | null
  fetched_at: string | null
}

export interface YearlyGrowthEntry {
  average_change_pct_per_year: number
  sale_pairs_count: number
}

export interface AreaPriceGrowth {
  area_name: string
  area_slug: string
  yearly_growth_data: Record<string, YearlyGrowthEntry>
}

// Matches the shape returned by API::V1::PropertiesController#property_detail
export interface PropertyDetail {
  id: number
  rightmove_id: string
  slug: string
  listing_url: string | null
  title: string | null
  description: string | null
  address_line_1: string | null
  town: string | null
  postcode: string | null
  price_pence: number | null
  price_qualifier: string | null
  price_per_sqft_pence: number | null
  property_type: string | null
  bedrooms: number | null
  bathrooms: number | null
  size_sqft: number | null
  tenure: string | null
  lease_years_remaining: number | null
  epc_rating: string | null
  council_tax_band: string | null
  service_charge_annual_pence: number | null
  photo_urls: string[]
  key_features: string[]
  latitude: number | null
  longitude: number | null
  agent_name: string | null
  agent_phone: string | null
  status: string
  listed_at: string | null
  noise: PropertyNoise | null
  nearest_stations: NearestStation[]
  area_price_growth: AreaPriceGrowth | null
}

// Matches the shape returned by API::V1::PropertiesController#property_summary
export interface Property {
  id: number
  rightmove_id: string
  title: string
  address: string
  price: number
  bedrooms: number
  bathrooms: number
  property_type: string
  status: string
  listed_at: string
  latitude: number
  longitude: number
  photo_url: string | null
  noise: PropertyNoise | null
  crime: PropertyCrime | null
  nearest_stations: NearestStation[]
}
