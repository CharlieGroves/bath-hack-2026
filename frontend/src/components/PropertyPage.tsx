import { useState } from 'react'
import { MapContainer, TileLayer, Marker } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts'
import { useProperty } from '../hooks/useProperty'
import type { PropertyDetail, AirQuality, YearlyGrowthEntry } from '../types/property'
import './PropertyPage.css'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon   from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
type LeafletDefaultIconPrototype = { _getIconUrl?: string }

delete (L.Icon.Default.prototype as LeafletDefaultIconPrototype)._getIconUrl
L.Icon.Default.mergeOptions({ iconRetinaUrl: markerIcon2x, iconUrl: markerIcon, shadowUrl: markerShadow })

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtPrice(pence: number | null) {
  if (pence == null) return '—'
  return '£' + Math.round(pence / 100).toLocaleString('en-GB')
}

function fmtLabel(s: string) {
  return s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
}

function fmtDate(iso: string | null) {
  if (!iso) return null
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
}

function fmtPct(value: number | null | undefined, digits = 1) {
  if (value == null || Number.isNaN(value)) return '—'
  return `${value > 0 ? '+' : ''}${value.toFixed(digits)}%`
}

// ── Sub-components ────────────────────────────────────────────────────────────

function BackBar({ onBack }: { onBack: () => void }) {
  return (
    <div className="pp-backbar">
      <button className="pp-back-btn" onClick={onBack}>
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M9 2L4 7l5 5" stroke="currentColor" strokeWidth="1.8"
                strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
        Back to search
      </button>
    </div>
  )
}

function HeroGallery({
  property,
  activePhoto,
  setActivePhoto,
}: {
  property: PropertyDetail
  activePhoto: number
  setActivePhoto: (i: number) => void
}) {
  const photos = property.photo_urls

  return (
    <div className="pp-hero-gallery">
      <div className="pp-gallery-stage">
        {photos.length > 0
          ? <img src={photos[activePhoto]} alt="" className="pp-gallery-img" />
          : <div className="pp-gallery-empty" />
        }

        {photos.length > 1 && (
          <>
            <button
              className="pp-gallery-arrow pp-gallery-prev"
              onClick={() => setActivePhoto((activePhoto - 1 + photos.length) % photos.length)}
              aria-label="Previous photo"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M11 3.5L5.5 9 11 14.5" stroke="currentColor" strokeWidth="2"
                      strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
            <button
              className="pp-gallery-arrow pp-gallery-next"
              onClick={() => setActivePhoto((activePhoto + 1) % photos.length)}
              aria-label="Next photo"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M7 3.5L12.5 9 7 14.5" stroke="currentColor" strokeWidth="2"
                      strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
          </>
        )}

        <div className="pp-gallery-overlay">
          {photos.length > 1 && (
            <span className="pp-gallery-counter">{activePhoto + 1} / {photos.length}</span>
          )}
          <div className="pp-overlay-content">
            <div className="pp-overlay-price">{fmtPrice(property.price_pence)}</div>
            <div className="pp-overlay-address">
              {property.address_line_1}
              {property.postcode && `, ${property.postcode}`}
            </div>
            <div className="pp-overlay-stats">
              {property.bedrooms != null && (
                <span className="pp-overlay-stat">
                  <strong>{property.bedrooms}</strong> bed
                </span>
              )}
              {property.bathrooms != null && (
                <span className="pp-overlay-stat">
                  <strong>{property.bathrooms}</strong> bath
                </span>
              )}
              {property.size_sqft != null && (
                <span className="pp-overlay-stat">
                  <strong>{property.size_sqft.toLocaleString('en-GB')}</strong> sq ft
                </span>
              )}
              {property.price_per_sqft_pence != null && (
                <span className="pp-overlay-stat pp-overlay-stat-dim">
                  {fmtPrice(property.price_per_sqft_pence)} / sq ft
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {photos.length > 1 && (
        <div className="pp-gallery-strip">
          {photos.map((url, i) => (
            <button
              key={i}
              className={`pp-thumb ${i === activePhoto ? 'pp-thumb-active' : ''}`}
              onClick={() => setActivePhoto(i)}
            >
              <img src={url} alt="" loading="lazy" />
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function CoreDetails({ property }: { property: PropertyDetail }) {
  const items: { label: string; value: string }[] = []

  if (property.property_type)    items.push({ label: 'Type',            value: fmtLabel(property.property_type) })
  if (property.tenure)           items.push({ label: 'Tenure',          value: fmtLabel(property.tenure) })
  if (property.epc_rating)       items.push({ label: 'EPC rating',      value: property.epc_rating })
  if (property.council_tax_band) items.push({ label: 'Council tax',     value: `Band ${property.council_tax_band}` })
  if (property.status && property.status !== 'active')
    items.push({ label: 'Status', value: fmtLabel(property.status) })
  if (property.listed_at)        items.push({ label: 'Listed',          value: fmtDate(property.listed_at) ?? '' })
  if (property.service_charge_annual_pence && property.service_charge_annual_pence > 0)
    items.push({ label: 'Service charge', value: `${fmtPrice(property.service_charge_annual_pence)} p.a.` })
  if (property.lease_years_remaining != null && property.tenure !== 'freehold')
    items.push({ label: 'Lease remaining', value: `${property.lease_years_remaining} years` })

  if (!items.length) return null

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Property details</h2>
      <div className="pp-details-grid">
        {items.map(({ label, value }) => (
          <div key={label} className="pp-detail-row">
            <span className="pp-detail-label">{label}</span>
            <span className="pp-detail-value">{value}</span>
          </div>
        ))}
      </div>
    </section>
  )
}

function KeyFeatures({ property }: { property: PropertyDetail }) {
  if (!property.key_features?.length) return null
  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Key features</h2>
      <ul className="pp-features">
        {property.key_features.map((f, i) => (
          <li key={i} className="pp-feature-item">{f}</li>
        ))}
      </ul>
    </section>
  )
}

function Description({ property }: { property: PropertyDetail }) {
  if (!property.description) return null
  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">About this property</h2>
      <p className="pp-description">{property.description}</p>
    </section>
  )
}

function TransportSection({ property }: { property: PropertyDetail }) {
  if (!property.nearest_stations?.length) return null

  const sorted = [...property.nearest_stations].sort((a, b) => a.walking_minutes - b.walking_minutes)

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Nearest stations</h2>
      <div className="pp-stations">
        {sorted.map((s, i) => (
          <div key={i} className="pp-station-row">
            <div className="pp-station-time">
              <span className="pp-station-mins">{s.walking_minutes}</span>
              <span className="pp-station-unit">min</span>
            </div>
            <div className="pp-station-vr" />
            <div className="pp-station-body">
              <div className="pp-station-name">{s.name}</div>
              <div className="pp-station-meta">
                <span className="pp-station-badge">{fmtLabel(s.transport_type)}</span>
                <span className="pp-station-dist">{Number(s.distance_miles).toFixed(1)} mi walk</span>
              </div>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}

function AreaGrowthChart({ property }: { property: PropertyDetail }) {
  const apg = property.area_price_growth
  if (!apg) return null

  const chartData = Object.entries(apg.yearly_growth_data)
    .map(([year, entry]) => ({
      year: parseInt(year, 10),
      pct: (entry as YearlyGrowthEntry).average_change_pct_per_year,
      pairs: (entry as YearlyGrowthEntry).sale_pairs_count,
    }))
    .filter(d => Math.abs(d.pct) <= 500 && d.pairs >= 3)
    .sort((a, b) => a.year - b.year)

  if (chartData.length < 2) return null

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Area price growth</h2>
      <p className="pp-section-sub">{apg.area_name}</p>
      <div className="pp-chart-wrap">
        <ResponsiveContainer width="100%" height={224}>
          <AreaChart data={chartData} margin={{ top: 8, right: 16, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="growthGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%"  stopColor="var(--ember)" stopOpacity={0.22} />
                <stop offset="95%" stopColor="var(--ember)" stopOpacity={0}    />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--hr)" vertical={false} />
            <XAxis
              dataKey="year"
              tick={{ fontSize: 11, fill: 'var(--t3)', fontFamily: 'var(--ff-body)' }}
              tickLine={false}
              axisLine={{ stroke: 'var(--border)' }}
            />
            <YAxis
              tickFormatter={(value: number | string) => {
                const numericValue = Number(value)
                return `${numericValue > 0 ? '+' : ''}${numericValue}%`
              }}
              tick={{ fontSize: 11, fill: 'var(--t3)', fontFamily: 'var(--ff-body)' }}
              tickLine={false}
              axisLine={false}
              width={52}
            />
            <Tooltip
              formatter={(value: number | string | readonly (number | string)[] | undefined) => {
                const numericValue = Number(Array.isArray(value) ? value[0] : value ?? 0)
                return [
                  `${numericValue > 0 ? '+' : ''}${numericValue.toFixed(1)}%`,
                  'Avg annual growth',
                ]
              }}
              contentStyle={{
                background: 'var(--card-bg)',
                border: '1px solid var(--border)',
                borderRadius: '8px',
                fontFamily: 'var(--ff-body)',
                fontSize: '12px',
                boxShadow: 'var(--shadow)',
              }}
              labelStyle={{ color: 'var(--t2)', fontWeight: 600 }}
            />
            <ReferenceLine y={0} stroke="var(--border)" strokeDasharray="4 2" />
            <Area
              type="monotone"
              dataKey="pct"
              stroke="var(--ember)"
              strokeWidth={2.5}
              fill="url(#growthGrad)"
              dot={{ fill: 'var(--ember)', r: 3, strokeWidth: 0 }}
              activeDot={{ fill: 'var(--coal)', r: 5, strokeWidth: 0 }}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </section>
  )
}

function ForecastSection({ property }: { property: PropertyDetail }) {
  const forecast = property.ml_forecast
  if (!forecast) return null

  const areaName = forecast.historical_context.area_name
  const localHpi = forecast.historical_context.local_hpi_yoy_pct
  const horizons = [...forecast.forecasts].sort((a, b) => a.prediction_horizon_months - b.prediction_horizon_months)

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">ML forecasts</h2>
      <p className="pp-section-sub">
        Trained on historical London sales for 1-year, 2-year, and 3-year horizons.
      </p>

      <div className="pp-forecast-card">
        <div className="pp-forecast-topline">
          <div className="pp-forecast-stat pp-forecast-stat-wide">
            <div className="pp-forecast-label">Current asking price</div>
            <div className="pp-forecast-value">{fmtPrice(forecast.current_price_pence)}</div>
          </div>
        </div>

        <div className="pp-forecast-meta">
          <span>
            Local HPI trend {fmtPct(localHpi)} · {areaName} · {forecast.historical_context.latest_hpi_period}
          </span>
          <span>{horizons.length} forecast horizons returned</span>
        </div>

        <div className="pp-forecast-horizon-grid">
          {horizons.map((item) => {
            const deltaPence = item.predicted_future_price_pence - forecast.current_price_pence
            const rmse = item.training_summary?.holdout_rmse_pounds

            return (
              <div key={item.prediction_horizon_months} className="pp-forecast-horizon-card">
                <div className="pp-forecast-label">
                  {item.prediction_horizon_years}-year forecast
                </div>
                <div className="pp-forecast-value pp-forecast-value-strong">
                  {fmtPrice(item.predicted_future_price_pence)}
                </div>
                <div className={`pp-forecast-horizon-delta ${deltaPence >= 0 ? 'pp-forecast-up' : 'pp-forecast-down'}`}>
                  {fmtPrice(deltaPence)} · {fmtPct(item.predicted_growth_pct)}
                </div>

                {rmse != null && (
                  <div className="pp-forecast-card-meta">
                    Holdout RMSE about £{Math.round(rmse).toLocaleString('en-GB')}
                  </div>
                )}
              </div>
            )
          })}
        </div>

        <div className="pp-forecast-note">{forecast.target_note}</div>
      </div>
    </section>
  )
}

const DAQI_COLORS: Record<string, string> = {
  Low:        '#22c55e',
  Moderate:   '#f59e0b',
  High:       '#f97316',
  'Very High': '#ef4444',
}

function AirQualitySection({ aq }: { aq: AirQuality }) {
  const color = DAQI_COLORS[aq.daqi_band] ?? 'var(--t3)'
  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Air quality</h2>
      <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
        <div style={{ fontSize: '2.5rem', fontWeight: 700, lineHeight: 1, color, fontFamily: 'var(--ff-body)' }}>
          {aq.daqi_index}
        </div>
        <div>
          <div style={{ fontWeight: 600, color, fontSize: '0.95rem' }}>{aq.daqi_band}</div>
          <div style={{ color: 'var(--t3)', fontSize: '0.8rem', marginTop: '0.2rem' }}>
            DAQI 1–10 · {aq.station_name}
          </div>
        </div>
      </div>
    </section>
  )
}

function NoiseSection({ property }: { property: PropertyDetail }) {
  const noise = property.noise
  if (!noise || noise.status === 'pending') {
    return (
      <section className="pp-section">
        <h2 className="pp-section-heading">Environmental data</h2>
        <p className="pp-pending">Environmental noise data is being gathered for this property.</p>
      </section>
    )
  }
  if (noise.status === 'failed') {
    return (
      <section className="pp-section">
        <h2 className="pp-section-heading">Environmental data</h2>
        <p className="pp-pending">Environmental data could not be retrieved for this property.</p>
      </section>
    )
  }
  return null
}

function AgentCard({ property }: { property: PropertyDetail }) {
  return (
    <div className="pp-agent-card">
      <div className="pp-agent-label">Listed by</div>
      {property.agent_name && <div className="pp-agent-name">{property.agent_name}</div>}
      {property.agent_phone && (
        <a className="pp-agent-phone" href={`tel:${property.agent_phone}`}>
          <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
            <path d="M1.5 1.5h2.75l1.25 3L3.75 5.75c.78 1.56 2 2.78 3.56 3.56L8.5 7.5l3 1.25V11.5c0 .55-.45 1-1 1C4.05 12.5.5 8.95.5 4.5c0-.55.45-1 1-1v-2Z"
                  stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          {property.agent_phone}
        </a>
      )}
      {property.listing_url && (
        <a
          className="pp-rightmove-link"
          href={property.listing_url}
          target="_blank"
          rel="noreferrer"
        >
          View on Rightmove
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
            <path d="M2.5 2.5h7m0 0v7m0-7L2.5 9.5" stroke="currentColor" strokeWidth="1.5"
                  strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </a>
      )}
    </div>
  )
}

function LocationMap({ property }: { property: PropertyDetail }) {
  if (property.latitude == null || property.longitude == null) return null
  const pos: [number, number] = [Number(property.latitude), Number(property.longitude)]

  return (
    <div className="pp-map-wrap">
      <MapContainer
        key={property.id}
        center={pos}
        zoom={15}
        style={{ height: '280px', width: '100%' }}
        zoomControl={false}
        attributionControl={false}
      >
        <TileLayer url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png" />
        <Marker position={pos} />
      </MapContainer>
    </div>
  )
}

// ── Main component ─────────────────────────────────────────────────────────────

interface Props {
  propertyId: number
  onBack: () => void
}

export default function PropertyPage({ propertyId, onBack }: Props) {
  const { property, loading, error } = useProperty(propertyId)
  const [activePhoto, setActivePhoto] = useState(0)

  if (loading) {
    return (
      <div className="pp-splash">
        <div className="pp-splash-spinner" />
        <div className="pp-splash-text">Loading property</div>
      </div>
    )
  }
  if (error) {
    return (
      <div className="pp-splash">
        <div className="pp-splash-text">Could not load property.</div>
        <button className="pp-back-btn" onClick={onBack} style={{ marginTop: 16 }}>
          Back to search
        </button>
      </div>
    )
  }
  if (!property) return null

  return (
    <div className="pp-shell">
      <BackBar onBack={onBack} />
      <div className="pp-scroll">
        <HeroGallery
          property={property}
          activePhoto={activePhoto}
          setActivePhoto={setActivePhoto}
        />
        <div className="pp-body">
          <div className="pp-main">
            <CoreDetails property={property} />
            <ForecastSection property={property} />
            <KeyFeatures property={property} />
            <Description property={property} />
            <TransportSection property={property} />
            {property.air_quality && <AirQualitySection aq={property.air_quality} />}
            <AreaGrowthChart property={property} />
            <NoiseSection property={property} />
          </div>
          <div className="pp-sidebar">
            <div className="pp-sidebar-sticky">
              <AgentCard property={property} />
              <LocationMap property={property} />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
