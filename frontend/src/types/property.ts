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
