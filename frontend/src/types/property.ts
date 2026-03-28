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

export interface AirQuality {
  daqi_index: number
  daqi_band: string
  station_name: string
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

export interface MlForecastAttribution {
  feature: string
  label: string
  attribution: number
  direction: 'up' | 'down'
  share_of_abs: number
}

export interface MlHistoricalContext {
  area_slug: string
  area_name: string
  latest_hpi_period: string
  local_hpi_yoy_pct: number | null
}

export interface MlTrainingSummary {
  prediction_horizon_months?: number
  prediction_horizon_years?: number
  sample_count: number
  holdout_count: number
  best_epoch: number
  trained_at: string
  holdout_rmse_pounds: number
  holdout_mape: number
  holdout_r2: number
  full_fit_rmse_pounds: number
}

export interface MlForecastResult {
  prediction_horizon_months: number
  prediction_horizon_years: number
  predicted_future_price_pence: number
  predicted_growth_pct: number | null
  baseline_prediction_pence: number
  training_summary: MlTrainingSummary | null
  attributions: MlForecastAttribution[]
  attribution_convergence_delta: number
}

export interface MlForecast {
  current_price_pence: number
  historical_context: MlHistoricalContext
  forecast_horizon_months: number[]
  training_summaries: Record<string, MlTrainingSummary>
  target_note: string
  forecasts: MlForecastResult[]
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
  status: string
  listed_at: string | null
  noise: PropertyNoise | null
  nearest_stations: NearestStation[]
  area_price_growth: AreaPriceGrowth | null
  air_quality: AirQuality | null
  ml_forecast: MlForecast | null
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
  nearest_stations: NearestStation[]
}
