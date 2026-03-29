export interface NearestStation {
  name: string
  distance_miles: number
  walking_minutes: number
  transport_type: string
  termini: string[]
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

export interface AirQuality {
  daqi_index: number
  daqi_band: string
  station_name: string
}

export interface FloodRisk {
  risk_level: string
  risk_band: number
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

export interface EstateAgent {
  display_name: string | null
  rating: number | null
  google_place_id: string | null
}

export interface MlPredictionInterval {
  lower_pence: number
  upper_pence: number
}

export interface MlForecastResult {
  years_ahead: number
  predicted_future_price_pence: number
  prediction_interval_95: MlPredictionInterval | null
}

export interface MlForecast {
  forecasts: MlForecastResult[]
}

export interface MlValuationInterval {
  lower_pence: number
  upper_pence: number
}

export interface MlValuationFeatureWeight {
  feature_key: string
  label: string
  display_value: string
  normalized_weight: number
  absolute_weight: number
  direction: 'positive' | 'negative'
}

export interface MlValuationFeatureCoverage {
  crime: boolean
  transport_noise: boolean
  air_quality: boolean
  stations: boolean
}

export interface MlValuation {
  predicted_current_price_pence: number
  pricing_signal: 'overpriced' | 'fairly_priced' | 'underpriced' | null
  price_gap_pence: number | null
  price_gap_pct: number | null
  prediction_interval_80: MlValuationInterval | null
  prediction_interval_95: MlValuationInterval | null
  model_source: 'out_of_fold' | 'full_model'
  feature_weights: MlValuationFeatureWeight[]
  model_feature_coverage?: MlValuationFeatureCoverage
  model_quality?: 'full_features' | 'partial_features'
}

export interface BoundingBox {
  north: number
  south: number
  east: number
  west: number
}

export interface SearchLocation {
  latitude: number
  longitude: number
  label: string
}

export interface IsochronePoint {
  latitude: number
  longitude: number
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
  estate_agent: EstateAgent | null
  status: string
  listed_at: string | null
  noise: PropertyNoise | null
  nearest_stations: NearestStation[]
  area_price_growth: AreaPriceGrowth | null
  air_quality: AirQuality | null
  ml_forecast: MlForecast | null
  ml_valuation: MlValuation | null
  flood_risk: FloodRisk | null
  crime: PropertyCrime | null
}

// Matches the shape returned by API::V1::PropertiesController#property_summary
export interface Property {
  id: number
  rightmove_id: string
  title: string
  address: string
  price: number
  price_per_sqft: number | null
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
  air_quality: AirQuality | null
  flood_risk: FloodRisk | null
  nearest_stations: NearestStation[]
  estate_agent: EstateAgent | null
}
