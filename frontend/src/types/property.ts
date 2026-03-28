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
}
