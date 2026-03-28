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

export interface BoundingBox {
  north: number
  south: number
  east: number
  west: number
}

export interface IsochroneCoordinate {
  latitude: number
  longitude: number
}

export interface SearchLocation {
  latitude: number
  longitude: number
  label: string
}

export interface PropertyLocationSearchResult {
  query: string
  location: SearchLocation
  transportation_type: string
  travel_time_seconds: number
  bounding_box: BoundingBox
  isochrone_shells: IsochroneCoordinate[][]
  properties: Property[]
  total: number
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
  latitude: number | string | null
  longitude: number | string | null
  photo_url: string | null
  noise: PropertyNoise | null
}
