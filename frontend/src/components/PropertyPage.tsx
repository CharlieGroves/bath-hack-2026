import { useState, useEffect } from 'react'
import { createPortal } from 'react-dom'
import { useNavigate } from 'react-router-dom'
import {
  AreaChart, Area, ComposedChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts'
import { useProperty } from '../hooks/useProperty'
import { useXray } from '../hooks/useXray'
import { useSimilarByImage } from '../hooks/useSimilarByImage'
import type { SimilarMatch, SimilarMode } from '../hooks/useSimilarByImage'
import type { PropertyDetail, YearlyGrowthEntry, MlValuation } from '../types/property'
import XrayMap from './XrayMap'
import './PropertyPage.css'

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

function fmtPct(value: number | null, digits = 1) {
  if (value == null || Number.isNaN(value)) return '—'
  return `${value > 0 ? '+' : ''}${value.toFixed(digits)}%`
}

function noiseLevel(db: number): { label: string; cls: string } {
  if (db < 50) return { label: 'Low', cls: 'env-green' }
  if (db < 60) return { label: 'Moderate', cls: 'env-amber' }
  if (db < 70) return { label: 'High', cls: 'env-orange' }
  return { label: 'Very High', cls: 'env-red' }
}

function primaryNoiseMetric(metrics: Record<string, number | null>): number | null {
  for (const key of ['lden', 'LDEN', 'lday', 'LDAY', 'lnight', 'LNIGHT']) {
    const v = metrics[key]
    if (v != null) return v
  }
  return Object.values(metrics).find(v => v != null) ?? null
}

function floodRiskCls(level: string): string {
  const l = level.toLowerCase()
  if (l.includes('very high') || l.includes('high')) return 'env-red'
  if (l.includes('medium')) return 'env-amber'
  return 'env-green'
}

function aqCls(band: string): string {
  if (band === 'Low') return 'env-green'
  if (band === 'Moderate') return 'env-amber'
  if (band === 'High') return 'env-orange'
  return 'env-red'
}

function pricingSignalLabel(signal: MlValuation['pricing_signal']) {
  switch (signal) {
    case 'overpriced':    return 'Overpriced'
    case 'underpriced':   return 'Underpriced'
    case 'fairly_priced': return 'Fair value'
    default:              return 'Model estimate'
  }
}

function pricingSignalCls(signal: MlValuation['pricing_signal']) {
  if (signal === 'underpriced') return 'pp-signal-under'
  if (signal === 'overpriced')  return 'pp-signal-over'
  return 'pp-signal-fair'
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

function HeroGallery({ property }: { property: PropertyDetail }) {
  const photos = property.photo_urls
  const [lightboxOpen, setLightboxOpen] = useState(false)
  const [lightboxPhoto, setLightboxPhoto] = useState(0)

  function openLightbox(i: number) {
    setLightboxPhoto(i)
    setLightboxOpen(true)
  }

  function lightboxPrev() {
    setLightboxPhoto(i => (i - 1 + photos.length) % photos.length)
  }

  function lightboxNext() {
    setLightboxPhoto(i => (i + 1) % photos.length)
  }

  useEffect(() => {
    if (!lightboxOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'ArrowLeft')  lightboxPrev()
      else if (e.key === 'ArrowRight') lightboxNext()
      else if (e.key === 'Escape')     setLightboxOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [lightboxOpen, photos.length])

  const sidePhotos = photos.slice(1, 5)

  return (
    <div className="pp-hero-gallery">
      {photos.length === 0 ? (
        <div className="pp-gallery-empty-wrap">
          <div className="pp-gallery-empty" />
          <div className="pp-gallery-overlay">
            <div className="pp-gallery-overlay-bottom">
              <div className="pp-overlay-content">
                <div className="pp-overlay-price">{fmtPrice(property.price_pence)}</div>
                <div className="pp-overlay-address">
                  {property.address_line_1}
                  {property.postcode && `, ${property.postcode}`}
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className={`pp-gallery-grid${sidePhotos.length === 0 ? ' pp-gallery-grid-single' : ''}`}>
          {/* Main photo */}
          <button className="pp-gallery-main" onClick={() => openLightbox(0)} aria-label="View photos">
            <img src={photos[0]} alt="" className="pp-gallery-main-img" />
            <div className="pp-gallery-overlay">
              <div className="pp-gallery-overlay-bottom">
                <div className="pp-overlay-content">
                  <div className="pp-overlay-price">{fmtPrice(property.price_pence)}</div>
                  <div className="pp-overlay-address">
                    {property.address_line_1}
                    {property.postcode && `, ${property.postcode}`}
                  </div>
                  <div className="pp-overlay-stats">
                    {property.bedrooms != null && (
                      <span className="pp-overlay-stat"><strong>{property.bedrooms}</strong> bed</span>
                    )}
                    {property.bathrooms != null && (
                      <span className="pp-overlay-stat"><strong>{property.bathrooms}</strong> bath</span>
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
                {photos.length > 1 && (
                  <div className="pp-gallery-view-all">
                    <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                      <rect x="0.75" y="0.75" width="4.5" height="3.5" rx="0.75" stroke="currentColor" strokeWidth="1.3"/>
                      <rect x="7.75" y="0.75" width="4.5" height="3.5" rx="0.75" stroke="currentColor" strokeWidth="1.3"/>
                      <rect x="0.75" y="8.75" width="4.5" height="3.5" rx="0.75" stroke="currentColor" strokeWidth="1.3"/>
                      <rect x="7.75" y="8.75" width="4.5" height="3.5" rx="0.75" stroke="currentColor" strokeWidth="1.3"/>
                    </svg>
                    View all {photos.length} photos
                  </div>
                )}
              </div>
            </div>
          </button>

          {/* Side thumbnails */}
          {sidePhotos.length > 0 && (
            <div className="pp-gallery-side">
              {sidePhotos.map((url, i) => (
                <button key={i} className="pp-gallery-side-thumb" onClick={() => openLightbox(i + 1)}>
                  <img src={url} alt="" loading="lazy" />
                  {i === 3 && photos.length > 5 && (
                    <div className="pp-gallery-more-overlay">+{photos.length - 5}</div>
                  )}
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Lightbox */}
      {lightboxOpen && createPortal(
        <div className="pp-lightbox" onClick={() => setLightboxOpen(false)}>
          <button className="pp-lightbox-close" onClick={() => setLightboxOpen(false)} aria-label="Close">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M2 2l12 12M14 2L2 14" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
            </svg>
          </button>

          {photos.length > 1 && (
            <button
              className="pp-lightbox-arrow pp-lightbox-prev"
              onClick={e => { e.stopPropagation(); lightboxPrev() }}
              aria-label="Previous photo"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M11.5 3L5.5 9l6 6" stroke="currentColor" strokeWidth="2"
                      strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
          )}

          <div className="pp-lightbox-stage" onClick={e => e.stopPropagation()}>
            <img src={photos[lightboxPhoto]} alt="" className="pp-lightbox-img" />
          </div>

          {photos.length > 1 && (
            <button
              className="pp-lightbox-arrow pp-lightbox-next"
              onClick={e => { e.stopPropagation(); lightboxNext() }}
              aria-label="Next photo"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M6.5 3L12.5 9l-6 6" stroke="currentColor" strokeWidth="2"
                      strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
          )}

          {photos.length > 1 && (
            <div className="pp-lightbox-counter">{lightboxPhoto + 1} / {photos.length}</div>
          )}
        </div>,
        document.body
      )}
    </div>
  )
}

function IntelligenceStrip({ property }: { property: PropertyDetail }) {
  const val = property.ml_valuation
  const forecast = property.ml_forecast
  const aq = property.air_quality
  const flood = property.flood_risk
  const noise = property.noise

  const oneYr = forecast?.forecasts.find(f => f.years_ahead === 1)
  const forecastPct = (oneYr && property.price_pence)
    ? ((oneYr.predicted_future_price_pence / property.price_pence) - 1) * 100
    : null

  const noiseDb = (noise && noise.status !== 'pending' && noise.status !== 'failed')
    ? (primaryNoiseMetric(noise.road_data?.metrics ?? {}) ??
       primaryNoiseMetric(noise.rail_data?.metrics ?? {}) ??
       primaryNoiseMetric(noise.flight_data?.metrics ?? {}))
    : null

  type Cell = { label: string; value: string; sub: string | null; cls: string }
  const cells: Cell[] = []

  if (val) cells.push({
    label: 'AI Model',
    value: pricingSignalLabel(val.pricing_signal),
    sub: val.price_gap_pct != null ? fmtPct(val.price_gap_pct) + ' vs ask' : null,
    cls: pricingSignalCls(val.pricing_signal),
  })

  if (forecastPct != null) cells.push({
    label: '1-yr forecast',
    value: fmtPct(forecastPct),
    sub: 'predicted change',
    cls: forecastPct >= 0 ? 'pp-intel-green' : 'pp-intel-red',
  })

  if (flood) cells.push({
    label: 'Flood risk',
    value: fmtLabel(flood.risk_level),
    sub: `Band ${flood.risk_band}`,
    cls: floodRiskCls(flood.risk_level),
  })

  if (aq) cells.push({
    label: 'Air quality',
    value: aq.daqi_band,
    sub: `DAQI ${aq.daqi_index} / 10`,
    cls: aqCls(aq.daqi_band),
  })

  if (noiseDb != null) {
    const nl = noiseLevel(noiseDb)
    cells.push({
      label: 'Noise level',
      value: `${Math.round(noiseDb)} dB`,
      sub: nl.label,
      cls: nl.cls,
    })
  }

  if (!cells.length) return null

  return (
    <div className="pp-intel-strip">
      <div className="pp-intel-brand">Hestia Intelligence</div>
      <div className="pp-intel-cells">
        {cells.map((c, i) => (
          <div key={i} className="pp-intel-cell">
            <div className="pp-intel-cell-label">{c.label}</div>
            <div className={`pp-intel-cell-value ${c.cls}`}>{c.value}</div>
            {c.sub && <div className="pp-intel-cell-sub">{c.sub}</div>}
          </div>
        ))}
      </div>
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
  if (property.lease_years_remaining != null && property.lease_years_remaining > 0 && property.tenure !== 'freehold')
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
      <h2 className="pp-section-heading">Transport links</h2>
      <p className="pp-section-sub">Walking times from this property — not shown on Rightmove</p>
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
              {s.termini?.length > 0 && (
                <div className="pp-station-termini">
                  {s.termini.join(", ")}
                </div>
              )}
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

  const currentPrice = property.price_pence
  const horizons = [...forecast.forecasts].sort((a, b) => a.years_ahead - b.years_ahead)

  const chartData = [
    {
      label: 'Now',
      predicted: currentPrice != null ? Math.round(currentPrice / 100) : null,
      lower: currentPrice != null ? Math.round(currentPrice / 100) : null,
      range: 0,
    },
    ...horizons.map((item) => {
      const predicted = Math.round(item.predicted_future_price_pence / 100)
      const lower = item.prediction_interval_95
        ? Math.round(item.prediction_interval_95.lower_pence / 100)
        : predicted
      const upper = item.prediction_interval_95
        ? Math.round(item.prediction_interval_95.upper_pence / 100)
        : predicted
      return {
        label: `${item.years_ahead} yr`,
        predicted,
        lower,
        range: upper - lower,
      }
    }),
  ]

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">ML forecasts</h2>
      <p className="pp-section-sub">
        Predicted prices for 1, 2, and 3 years ahead with an approximate 95% range.
      </p>

      <div className="pp-chart-wrap">
        <ResponsiveContainer width="100%" height={224}>
          <ComposedChart data={chartData} margin={{ top: 8, right: 16, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="forecastBand" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%"   stopColor="var(--ember)" stopOpacity={0.18} />
                <stop offset="100%" stopColor="var(--ember)" stopOpacity={0.06} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--hr)" vertical={false} />
            <XAxis
              dataKey="label"
              tick={{ fontSize: 11, fill: 'var(--t3)', fontFamily: 'var(--ff-body)' }}
              tickLine={false}
              axisLine={{ stroke: 'var(--border)' }}
            />
            <YAxis
              tickFormatter={(v: number) => `£${Math.round(v / 1000)}k`}
              tick={{ fontSize: 11, fill: 'var(--t3)', fontFamily: 'var(--ff-body)' }}
              tickLine={false}
              axisLine={false}
              width={52}
            />
            <Tooltip
              content={({ active, payload, label }) => {
                if (!active || !payload?.length) return null
                const item = payload.find(p => p.dataKey === 'predicted')
                if (!item) return null
                return (
                  <div style={{
                    background: 'var(--card-bg)',
                    border: '1px solid var(--border)',
                    borderRadius: '8px',
                    padding: '8px 12px',
                    fontFamily: 'var(--ff-body)',
                    fontSize: '12px',
                    boxShadow: 'var(--shadow)',
                  }}>
                    <div style={{ color: 'var(--t2)', fontWeight: 600, marginBottom: 4 }}>{label}</div>
                    <div style={{ color: 'var(--t1)' }}>
                      {`£${Math.round(Number(item.value)).toLocaleString('en-GB')}`}
                    </div>
                  </div>
                )
              }}
            />
            <Area
              type="monotone"
              dataKey="lower"
              stackId="band"
              fill="transparent"
              stroke="none"
            />
            <Area
              type="monotone"
              dataKey="range"
              stackId="band"
              fill="url(#forecastBand)"
              stroke="none"
            />
            <Line
              type="monotone"
              dataKey="predicted"
              stroke="var(--ember)"
              strokeWidth={2.5}
              dot={{ fill: 'var(--ember)', r: 4, strokeWidth: 0 }}
              activeDot={{ fill: 'var(--coal)', r: 5, strokeWidth: 0 }}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </div>

      <div className="pp-forecast-card">
        <div className="pp-forecast-horizon-grid">
          {horizons.map((item) => {
            const deltaPence = currentPrice == null ? null : item.predicted_future_price_pence - currentPrice
            const impliedGrowthPct = currentPrice
              ? ((item.predicted_future_price_pence / currentPrice) - 1) * 100
              : null

            return (
              <div key={item.years_ahead} className="pp-forecast-horizon-card">
                <div className="pp-forecast-label">
                  {item.years_ahead}-year forecast
                </div>
                <div className="pp-forecast-value pp-forecast-value-strong">
                  {fmtPrice(item.predicted_future_price_pence)}
                </div>

                {deltaPence != null && (
                  <div className={`pp-forecast-horizon-delta ${deltaPence >= 0 ? 'pp-forecast-up' : 'pp-forecast-down'}`}>
                    {fmtPrice(deltaPence)} · {impliedGrowthPct != null ? `${impliedGrowthPct > 0 ? '+' : ''}${impliedGrowthPct.toFixed(1)}%` : '—'}
                  </div>
                )}

                {item.prediction_interval_95 && (
                  <div className="pp-forecast-range">
                    95% range {fmtPrice(item.prediction_interval_95.lower_pence)} to {fmtPrice(item.prediction_interval_95.upper_pence)}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}

function ValuationSection({ property }: { property: PropertyDetail }) {
  const val = property.ml_valuation
  if (!val) return null

  const signalCls = pricingSignalCls(val.pricing_signal)

  return (
    <section className="pp-section pp-section-ai">
      <div className="pp-section-ai-tag">Hestia AI</div>
      <h2 className="pp-section-heading">Model valuation</h2>

      <div className="pp-val-card">
        <div className={`pp-val-banner ${signalCls}`}>
          {pricingSignalLabel(val.pricing_signal)}
          {val.price_gap_pct != null && (
            <span className="pp-val-banner-pct">{fmtPct(val.price_gap_pct)} vs asking price</span>
          )}
        </div>

        <div className="pp-val-body">
          <div className="pp-val-main">
            <div className="pp-val-label">Model fair value</div>
            <div className="pp-val-price">{fmtPrice(val.predicted_current_price_pence)}</div>
            {val.prediction_interval_80 && (
              <div className="pp-val-band">
                80% band: {fmtPrice(val.prediction_interval_80.lower_pence)} – {fmtPrice(val.prediction_interval_80.upper_pence)}
              </div>
            )}
          </div>
          <div className="pp-val-meta">
            {property.price_pence != null && (
              <div className="pp-val-stat">
                <span>Asking price</span>
                <strong>{fmtPrice(property.price_pence)}</strong>
              </div>
            )}
            {val.price_gap_pence != null && (
              <div className="pp-val-stat">
                <span>Gap vs model</span>
                <strong className={val.price_gap_pence >= 0 ? 'pp-val-over' : 'pp-val-under'}>
                  {fmtPrice(val.price_gap_pence)}
                </strong>
              </div>
            )}
            <div className="pp-val-stat">
              <span>Estimate basis</span>
              <strong>{val.model_source === 'out_of_fold' ? 'Out-of-fold' : 'Full model'}</strong>
            </div>
            {val.model_quality && (
              <div className="pp-val-stat">
                <span>Data coverage</span>
                <strong>{val.model_quality === 'full_features' ? 'Full' : 'Partial'}</strong>
              </div>
            )}
          </div>
        </div>

        {val.feature_weights.length > 0 && (
          <div className="pp-val-weights">
            <div className="pp-val-weights-heading">What's driving this valuation</div>
            {val.feature_weights.map(w => (
              <div key={`${w.feature_key}-${w.label}`} className="pp-weight-row">
                <div className="pp-weight-head">
                  <div>
                    <div className="pp-weight-label">{w.label}</div>
                    <div className="pp-weight-value">{w.display_value}</div>
                  </div>
                  <div className={`pp-weight-score ${w.direction === 'positive' ? 'pp-forecast-up' : 'pp-forecast-down'}`}>
                    {fmtPct(w.normalized_weight * 100, 1)}
                  </div>
                </div>
                <div className="pp-weight-track">
                  <div
                    className={`pp-weight-fill ${w.direction === 'positive' ? 'pp-weight-fill-positive' : 'pp-weight-fill-negative'}`}
                    style={{ width: `${Math.max(w.absolute_weight * 100, 6)}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  )
}

function SimilarPropertiesSection({
  matches, loading, error, activeMode,
  onFindSimilar, onFindSimilarMaxpool, onSelect, onClose,
}: {
  matches: SimilarMatch[]
  loading: boolean
  error: string | null
  activeMode: SimilarMode | null
  onFindSimilar: () => void
  onFindSimilarMaxpool: () => void
  onSelect: (id: number) => void
  onClose: () => void
}) {
  const hasResults = !loading && !error && matches.length > 0

  return (
    <section className="pp-section pp-section-ai">
      <div className="pp-section-ai-tag">Hestia AI</div>
      <h2 className="pp-section-heading">Visual similarity search</h2>
      <p className="pp-section-sub">
        Our computer vision model finds properties that look aesthetically similar to this one.
      </p>

      <div className="pp-similar-triggers">
        <button
          className={`pp-similar-trigger${activeMode === 'per_photo' ? ' active' : ''}`}
          onClick={onFindSimilar}
          disabled={loading}
        >
          {loading && activeMode === 'per_photo'
            ? <span className="pp-similar-btn-spinner" />
            : <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <circle cx="5.5" cy="5.5" r="4" stroke="currentColor" strokeWidth="1.5"/>
                <path d="M8.5 8.5L13 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
                <path d="M3.5 5.5h4M5.5 3.5v4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/>
              </svg>
          }
          Match this photo
        </button>
        <button
          className={`pp-similar-trigger${activeMode === 'maxpool' ? ' active' : ''}`}
          onClick={onFindSimilarMaxpool}
          disabled={loading}
        >
          {loading && activeMode === 'maxpool'
            ? <span className="pp-similar-btn-spinner" />
            : <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <circle cx="5.5" cy="5.5" r="4" stroke="currentColor" strokeWidth="1.5"/>
                <path d="M8.5 8.5L13 13" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
              </svg>
          }
          Match all photos
        </button>
      </div>

      {loading && (
        <div className="pp-similar-state">
          <span className="pp-similar-spinner" />
          <span className="pp-similar-state-text">Searching for similar properties</span>
        </div>
      )}

      {error && !loading && (
        <div className="pp-similar-state">
          <span className="pp-similar-state-text pp-similar-error">Could not find similar properties.</span>
        </div>
      )}

      {hasResults && (
        <div className="pp-similar-results">
          <div className="pp-similar-results-header">
            <span className="pp-similar-results-label">
              {activeMode === 'maxpool' ? 'Matched using all photos' : 'Matched using this photo'}
              {' '}· {matches.length} results
            </span>
            <button className="pp-similar-close" onClick={onClose} aria-label="Clear results">
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M2 2l10 10M12 2L2 12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
              </svg>
            </button>
          </div>
          <div className="pp-similar-scroll">
            {matches.map(m => (
              <button key={m.id} className="pp-similar-card" onClick={() => onSelect(m.id)}>
                <div className="pp-similar-card-img">
                  {m.photo_url
                    ? <img src={m.photo_url} alt="" loading="lazy" />
                    : <div className="pp-similar-card-img-empty" />
                  }
                </div>
                <div className="pp-similar-card-body">
                  <div className="pp-similar-card-price">
                    {m.price != null ? '£' + Math.round(m.price / 100).toLocaleString('en-GB') : '—'}
                  </div>
                  <div className="pp-similar-card-address">{m.address}</div>
                  {m.bedrooms != null && (
                    <div className="pp-similar-card-meta">{m.bedrooms} bed</div>
                  )}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  )
}

function EnvironmentalSection({ property }: { property: PropertyDetail }) {
  const aq = property.air_quality
  const flood = property.flood_risk
  const noise = property.noise
  const crime = property.crime

  const noiseReady = noise && noise.status !== 'pending' && noise.status !== 'failed'

  const hasAny = aq || flood || noiseReady || (crime && crime.status !== 'pending')
  if (!hasAny) return null

  return (
    <section className="pp-section">
      <h2 className="pp-section-heading">Environmental data</h2>
      <p className="pp-section-sub">Data exclusive to Hestia — not shown on Rightmove</p>
      <div className="pp-env-grid">

        {aq && (() => {
          const cls = aqCls(aq.daqi_band)
          return (
            <div className={`pp-env-card ${cls}`}>
              <div className="pp-env-card-indicator" />
              <div className="pp-env-card-label">Air quality</div>
              <div className="pp-env-card-value">{aq.daqi_index}<span className="pp-env-card-unit"> / 10</span></div>
              <div className={`pp-env-card-band ${cls}`}>{aq.daqi_band}</div>
              <div className="pp-env-card-meta">DAQI scale · {aq.station_name}</div>
            </div>
          )
        })()}

        {flood && (() => {
          const cls = floodRiskCls(flood.risk_level)
          return (
            <div className={`pp-env-card ${cls}`}>
              <div className="pp-env-card-indicator" />
              <div className="pp-env-card-label">Flood risk</div>
              <div className="pp-env-card-value pp-env-card-value-text">{fmtLabel(flood.risk_level)}</div>
              <div className={`pp-env-card-band ${cls}`}>Band {flood.risk_band}</div>
              <div className="pp-env-card-meta">Environment Agency</div>
            </div>
          )
        })()}

        {noiseReady && [
          { key: 'road',   label: 'Road noise',   src: noise!.road_data },
          { key: 'rail',   label: 'Rail noise',   src: noise!.rail_data },
          { key: 'flight', label: 'Flight noise', src: noise!.flight_data },
        ].map(({ key, label, src }) => {
          if (!src) return null
          const db = src.covered ? primaryNoiseMetric(src.metrics) : null
          const nl = db != null ? noiseLevel(db) : null
          return (
            <div key={key} className={`pp-env-card${nl ? ` ${nl.cls}` : ''}`}>
              <div className="pp-env-card-indicator" />
              <div className="pp-env-card-label">{label}</div>
              {db != null && nl ? (
                <>
                  <div className="pp-env-card-value">{Math.round(db)}<span className="pp-env-card-unit"> dB</span></div>
                  <div className={`pp-env-card-band ${nl.cls}`}>{nl.label}</div>
                  <div className="pp-env-card-meta">LDEN · UK Noise Atlas</div>
                </>
              ) : (
                <div className="pp-env-card-na">{src.covered ? 'No data' : 'Not applicable'}</div>
              )}
            </div>
          )
        })}

        {crime && crime.status !== 'pending' && crime.avg_monthly_crimes != null && (
          <div className="pp-env-card">
            <div className="pp-env-card-indicator" />
            <div className="pp-env-card-label">Local crime</div>
            <div className="pp-env-card-value">
              {crime.avg_monthly_crimes.toFixed(1)}
              <span className="pp-env-card-unit"> /mo</span>
            </div>
            <div className="pp-env-card-meta">Average monthly incidents</div>
          </div>
        )}

      </div>
    </section>
  )
}

function AgentCard({ property }: { property: PropertyDetail }) {
  return (
    <div className="pp-agent-card">
      <div className="pp-agent-label">Listed by</div>
      {property.agent_name && <div className="pp-agent-name">{property.agent_name}</div>}
      {property.estate_agent?.rating != null && (
        <div className="pp-agent-rating">{property.estate_agent.rating.toFixed(1)} / 5 on Google</div>
      )}
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

// ── Main component ─────────────────────────────────────────────────────────────

interface Props {
  propertyId: number
  onBack: () => void
}

export default function PropertyPage({ propertyId, onBack }: Props) {
  const { property, loading, error } = useProperty(propertyId)
  const { xray, loading: xrayLoading } = useXray(property ? property.id : null)
  const { matches: similarMatches, loading: similarLoading, error: similarError, activeMode: similarMode, fetchSimilar, fetchSimilarMaxpool, clear: clearSimilar } = useSimilarByImage()
  const navigate = useNavigate()

  function handleFindSimilar() {
    if (!property) return
    fetchSimilar(property.id, 0)
  }

  function handleFindSimilarMaxpool() {
    if (!property) return
    fetchSimilarMaxpool(property.id)
  }

  function handleCloseSimilar() {
    clearSimilar()
  }

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
        <HeroGallery property={property} />
        <IntelligenceStrip property={property} />
        <div className="pp-body">
          <div className="pp-main">
            <ValuationSection property={property} />
            <SimilarPropertiesSection
              matches={similarMatches}
              loading={similarLoading}
              error={similarError}
              activeMode={similarMode}
              onFindSimilar={handleFindSimilar}
              onFindSimilarMaxpool={handleFindSimilarMaxpool}
              onSelect={id => navigate(`/properties/${id}`)}
              onClose={handleCloseSimilar}
            />
            <ForecastSection property={property} />
            <EnvironmentalSection property={property} />
            <TransportSection property={property} />
            <CoreDetails property={property} />
            <KeyFeatures property={property} />
            <Description property={property} />
            <AreaGrowthChart property={property} />
          </div>
          <div className="pp-sidebar">
            <div className="pp-sidebar-sticky">
              <AgentCard property={property} />
              <div className="pp-xray-wrap">
                <div className="pp-xray-heading">
                  <div className="pp-section-ai-tag" style={{ marginBottom: 4 }}>Hestia XRay</div>
                  <p className="pp-xray-sub">Walking isochrones, schools, shops, pharmacies</p>
                </div>
                <XrayMap property={property} xray={xray} loading={xrayLoading} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
