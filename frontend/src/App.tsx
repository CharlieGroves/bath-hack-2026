import { useState, useMemo } from 'react'
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import type { Property } from './types/property'
import { useProperties } from './hooks/useProperties'
import './App.css'

import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

delete (L.Icon.Default.prototype as any)._getIconUrl
L.Icon.Default.mergeOptions({ iconRetinaUrl: markerIcon2x, iconUrl: markerIcon, shadowUrl: markerShadow })

// ─── Mock enrichment ────────────────────────────────────────────────────────
// These fields would be populated from:
//   Crime:       police.uk API  (free, open)
//   Schools:     Ofsted API     (free, open)
//   Flood:       Environment Agency API (free)
//   Walk score:  OSM Overpass   (distance to amenities)
//   Commute:     NRE / TfL API  (station → destination time)
//   Broadband:   Ofcom API      (postcode lookup)

type CrimeLevel  = 'Low' | 'Medium' | 'High'
type SchoolRating = 'Outstanding' | 'Good' | 'Requires Improvement' | 'Inadequate'
type FloodRisk   = 'Very Low' | 'Low' | 'Medium' | 'High'

interface Enrichment {
  crimeLevel:         CrimeLevel
  schoolRating:       SchoolRating
  floodRisk:          FloodRisk
  walkScore:          number
  broadbandMbps:      number
  commuteMin:         number
  nearestStationMi:   number
  nearestStationName: string
}

const STATION_NAMES = [
  'Bath Spa', 'Bristol Temple Meads', 'Swindon', 'Chippenham',
  'Bradford-on-Avon', 'Trowbridge', 'Frome', 'Keynsham',
]

function sr(id: number, s: number) {
  const x = Math.sin(id * 23 + s * 97) * 10000
  return x - Math.floor(x)
}

function getEnrichment(id: number): Enrichment {
  const crime  = (['Low', 'Low', 'Medium', 'Medium', 'High'] as CrimeLevel[])       [Math.floor(sr(id, 1) * 5)]
  const school = (['Outstanding', 'Good', 'Good', 'Requires Improvement', 'Inadequate'] as SchoolRating[])[Math.floor(sr(id, 2) * 5)]
  const flood  = (['Very Low', 'Very Low', 'Low', 'Medium', 'High'] as FloodRisk[])[Math.floor(sr(id, 3) * 5)]
  return {
    crimeLevel:         crime,
    schoolRating:       school,
    floodRisk:          flood,
    walkScore:          Math.floor(sr(id, 4) * 55) + 30,
    broadbandMbps:      [80, 150, 300, 500, 900][Math.floor(sr(id, 5) * 5)],
    commuteMin:         Math.floor(sr(id, 6) * 40) + 12,
    nearestStationMi:   Math.round((sr(id, 7) * 1.2 + 0.1) * 10) / 10,
    nearestStationName: STATION_NAMES[Math.floor(sr(id, 8) * STATION_NAMES.length)],
  }
}

// ─── Score lookup tables ────────────────────────────────────────────────────
const CRIME_CLR:  Record<CrimeLevel, string>  = { Low: '#83B366', Medium: '#DC8236', High: '#B8210F' }
const SCHOOL_CLR: Record<SchoolRating, string> = {
  Outstanding: '#83B366', Good: '#83B366',
  'Requires Improvement': '#DC8236', Inadequate: '#B8210F',
}
const FLOOD_CLR:  Record<FloodRisk, string>   = {
  'Very Low': '#83B366', Low: '#83B366', Medium: '#DC8236', High: '#B8210F',
}
const CRIME_ORD:  Record<CrimeLevel, number>  = { Low: 0, Medium: 1, High: 2 }
const SCHOOL_ORD: Record<SchoolRating, number> = {
  Outstanding: 0, Good: 1, 'Requires Improvement': 2, Inadequate: 3,
}
const FLOOD_ORD:  Record<FloodRisk, number>   = { 'Very Low': 0, Low: 1, Medium: 2, High: 3 }

// ─── Helpers ────────────────────────────────────────────────────────────────
function fmtPrice(pence: number) {
  return '£' + Math.round(pence / 100).toLocaleString('en-GB')
}

function fmtLabel(s: string) {
  return s.replace(/_/g, '-').replace(/\b\w/g, c => c.toUpperCase())
}

// ─── Filter state ───────────────────────────────────────────────────────────
interface Filters {
  minPrice:    number | ''
  maxPrice:    number | ''
  minBeds:     number
  types:       string[]
  maxCrime:    CrimeLevel | 'Any'
  minSchool:   SchoolRating | 'Any'
  maxFlood:    FloodRisk | 'Any'
  maxCommute:  number | ''
  minWalk:     number
  minBroadband: number
}

const INIT: Filters = {
  minPrice: '', maxPrice: '', minBeds: 0, types: [],
  maxCrime: 'Any', minSchool: 'Any', maxFlood: 'Any',
  maxCommute: '', minWalk: 0, minBroadband: 0,
}

// ─── SVG Icons ──────────────────────────────────────────────────────────────
function FlameIcon({ size = 24 }: { size?: number }) {
  return (
    <svg width={size} height={size * 1.2} viewBox="0 0 20 24" fill="none">
      <path d="M10 1C10 1 3 9 3 15.5a7 7 0 0014 0C17 9.5 10 1 10 1z" fill="#E76814"/>
      <path d="M10 9C10 9 7 13.5 7 16.5a3 3 0 006 0C13 13.5 10 9 10 9z" fill="#F25016"/>
      <ellipse cx="10" cy="19" rx="2" ry="1.4" fill="#DC8236"/>
    </svg>
  )
}

function GridIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" fill="currentColor">
      <rect x="0" y="0" width="6" height="6" rx="1.2"/>
      <rect x="9" y="0" width="6" height="6" rx="1.2"/>
      <rect x="0" y="9" width="6" height="6" rx="1.2"/>
      <rect x="9" y="9" width="6" height="6" rx="1.2"/>
    </svg>
  )
}

function MapIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" fill="currentColor">
      <path d="M7.5 1a5 5 0 100 10 5 5 0 000-10zm0 2a3 3 0 110 6 3 3 0 010-6z"/>
      <path d="M7.5 10.5l-2.5 4h5l-2.5-4z"/>
    </svg>
  )
}

// ─── Main App ────────────────────────────────────────────────────────────────
type EnrichedProperty = Property & { enrichment: Enrichment }

export default function App() {
  const { properties, loading, error } = useProperties()
  const [filters, setFilters]     = useState<Filters>(INIT)
  const [view, setView]           = useState<'grid' | 'map'>('grid')
  const [destination, setDest]    = useState('Bath Spa')

  const enriched = useMemo<EnrichedProperty[]>(
    () => properties.map(p => ({ ...p, enrichment: getEnrichment(p.id) })),
    [properties]
  )

  const filtered = useMemo(() => enriched.filter(p => {
    const e = p.enrichment
    if (filters.minPrice !== '' && p.price < (filters.minPrice as number) * 100) return false
    if (filters.maxPrice !== '' && p.price > (filters.maxPrice as number) * 100) return false
    if (filters.minBeds > 0 && (p.bedrooms ?? 0) < filters.minBeds) return false
    if (filters.types.length && !filters.types.includes(p.property_type)) return false
    if (filters.maxCrime !== 'Any' && CRIME_ORD[e.crimeLevel] > CRIME_ORD[filters.maxCrime as CrimeLevel]) return false
    if (filters.minSchool !== 'Any' && SCHOOL_ORD[e.schoolRating] > SCHOOL_ORD[filters.minSchool as SchoolRating]) return false
    if (filters.maxFlood  !== 'Any' && FLOOD_ORD[e.floodRisk] > FLOOD_ORD[filters.maxFlood as FloodRisk]) return false
    if (filters.maxCommute !== '' && e.commuteMin > (filters.maxCommute as number)) return false
    if (e.walkScore < filters.minWalk) return false
    if (e.broadbandMbps < filters.minBroadband) return false
    return true
  }), [enriched, filters])

  function setF<K extends keyof Filters>(k: K, v: Filters[K]) {
    setFilters(f => ({ ...f, [k]: v }))
  }
  function toggleType(t: string) {
    setFilters(f => ({
      ...f,
      types: f.types.includes(t) ? f.types.filter(x => x !== t) : [...f.types, t],
    }))
  }

  if (loading) return (
    <div className="splash">
      <FlameIcon size={40} />
      <p className="splash-text">Finding your perfect home…</p>
    </div>
  )
  if (error) return <div className="splash"><p>Error: {error}</p></div>

  return (
    <div className="app">

      {/* ── Header ── */}
      <header className="header">
        <div className="header-brand">
          <FlameIcon size={22} />
          <span className="brand-name">Hearthstone</span>
        </div>

        <div className="header-search-wrap">
          <svg className="search-icon" width="15" height="15" viewBox="0 0 15 15" fill="none">
            <circle cx="6.5" cy="6.5" r="5" stroke="currentColor" strokeWidth="1.5"/>
            <path d="M10.5 10.5L14 14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
          </svg>
          <input className="header-search" type="text" placeholder="Town, postcode, or area…" />
        </div>

        <div className="header-actions">
          <span className="count-badge">
            {filtered.length.toLocaleString()} <span>of {enriched.length.toLocaleString()}</span>
          </span>
          <div className="view-switch">
            <button className={`vsw-btn ${view === 'grid' ? 'on' : ''}`} onClick={() => setView('grid')}>
              <GridIcon /> Grid
            </button>
            <button className={`vsw-btn ${view === 'map' ? 'on' : ''}`} onClick={() => setView('map')}>
              <MapIcon /> Map
            </button>
          </div>
        </div>
      </header>

      <div className="shell">

        {/* ── Sidebar ── */}
        <aside className="sidebar">
          <div className="sb-inner">

            {/* Standard filters */}
            <section className="sb-section">
              <h4 className="sb-label">Price Range</h4>
              <div className="price-row">
                <div className="price-box">
                  <span>£</span>
                  <input type="number" placeholder="Min"
                    value={filters.minPrice}
                    onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)} />
                </div>
                <span className="price-dash">—</span>
                <div className="price-box">
                  <span>£</span>
                  <input type="number" placeholder="Max"
                    value={filters.maxPrice}
                    onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)} />
                </div>
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Min Bedrooms</h4>
              <div className="pill-row">
                {[0, 1, 2, 3, 4, 5].map(n => (
                  <button
                    key={n}
                    className={`pill ${filters.minBeds === n ? 'pill-on' : ''}`}
                    onClick={() => setF('minBeds', n)}
                  >{n === 0 ? 'Any' : `${n}+`}</button>
                ))}
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Property Type</h4>
              <div className="check-grid">
                {['flat', 'terraced', 'semi_detached', 'detached', 'bungalow'].map(t => (
                  <label key={t} className={`check-pill ${filters.types.includes(t) ? 'check-on' : ''}`}>
                    <input type="checkbox" checked={filters.types.includes(t)} onChange={() => toggleType(t)} />
                    {t === 'semi_detached' ? 'Semi' : fmtLabel(t)}
                  </label>
                ))}
              </div>
            </section>

            {/* Enriched filters */}
            <div className="enriched-header">
              <FlameIcon size={16} />
              <span>Beyond Rightmove</span>
            </div>
            <p className="enriched-sub">Filters Rightmove doesn't offer</p>

            <section className="sb-section">
              <h4 className="sb-label">Commute to</h4>
              <input
                className="text-field"
                type="text"
                placeholder="e.g. Bath Spa, Paddington…"
                value={destination}
                onChange={e => setDest(e.target.value)}
              />
              <div className="inline-row">
                <span className="dim">Max</span>
                <input className="num-field" type="number" placeholder="45"
                  value={filters.maxCommute}
                  onChange={e => setF('maxCommute', e.target.value === '' ? '' : +e.target.value)} />
                <span className="dim">mins by train</span>
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Nearest School (Ofsted, min)</h4>
              <div className="pill-row wrap">
                {(['Any', 'Good', 'Outstanding'] as const).map(v => (
                  <button key={v}
                    className={`pill ${filters.minSchool === v ? 'pill-on' : ''}`}
                    onClick={() => setF('minSchool', v)}
                  >{v}</button>
                ))}
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Crime Level (max)</h4>
              <div className="pill-row wrap">
                {(['Any', 'Medium', 'Low'] as const).map(v => (
                  <button key={v}
                    className={`pill ${filters.maxCrime === v ? 'pill-on' : ''}`}
                    onClick={() => setF('maxCrime', v)}
                  >{v}</button>
                ))}
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Flood Risk (max)</h4>
              <div className="pill-row wrap">
                {(['Any', 'Medium', 'Low', 'Very Low'] as const).map(v => (
                  <button key={v}
                    className={`pill ${filters.maxFlood === v ? 'pill-on' : ''}`}
                    onClick={() => setF('maxFlood', v)}
                  >{v}</button>
                ))}
              </div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Min Walk Score — <strong>{filters.minWalk}</strong></h4>
              <input type="range" className="slider" min={0} max={90} step={10}
                value={filters.minWalk}
                onChange={e => setF('minWalk', +e.target.value)} />
              <div className="slider-labels"><span>0</span><span>90</span></div>
            </section>

            <section className="sb-section">
              <h4 className="sb-label">Min Broadband</h4>
              <div className="pill-row wrap">
                {([0, 80, 150, 300, 500] as const).map(v => (
                  <button key={v}
                    className={`pill ${filters.minBroadband === v ? 'pill-on' : ''}`}
                    onClick={() => setF('minBroadband', v)}
                  >{v === 0 ? 'Any' : `${v}Mb+`}</button>
                ))}
              </div>
            </section>

            <button className="reset-btn" onClick={() => setFilters(INIT)}>
              Reset all filters
            </button>
          </div>
        </aside>

        {/* ── Content ── */}
        <main className="content">
          {view === 'grid' ? (
            <div className="grid">
              {filtered.slice(0, 60).map(p => (
                <PropertyCard key={p.id} p={p} destination={destination} />
              ))}
              {filtered.length === 0 && (
                <div className="empty">
                  <FlameIcon size={32} />
                  <p>No properties match your filters.</p>
                  <button className="reset-btn" onClick={() => setFilters(INIT)}>Clear filters</button>
                </div>
              )}
            </div>
          ) : (
            <div className="map-wrap">
              <MapContainer center={[51.38, -2.36]} zoom={11} style={{ height: '100%', width: '100%' }}>
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />
                {filtered
                  .filter(p => p.latitude != null && p.longitude != null)
                  .slice(0, 300)
                  .map(p => (
                    <Marker key={p.id} position={[p.latitude, p.longitude]}>
                      <Popup>
                        <strong>{p.title || p.address}</strong><br/>
                        {fmtPrice(p.price)}<br/>
                        🛡 Crime: {p.enrichment.crimeLevel} &nbsp;
                        🏫 School: {p.enrichment.schoolRating}<br/>
                        🚂 {p.enrichment.commuteMin}min to {destination}
                      </Popup>
                    </Marker>
                  ))
                }
              </MapContainer>
            </div>
          )}
        </main>

      </div>
    </div>
  )
}

// ─── Property Card ───────────────────────────────────────────────────────────
function PropertyCard({ p, destination }: { p: EnrichedProperty; destination: string }) {
  const e = p.enrichment

  return (
    <article className="card">
      <a
        href={`https://www.rightmove.co.uk/properties/${p.rightmove_id}`}
        target="_blank" rel="noreferrer"
        className="card-link"
      >
        <div className="card-img">
          {p.photo_url
            ? <img src={p.photo_url} alt="" loading="lazy" />
            : <div className="img-placeholder"><FlameIcon size={28} /></div>
          }
          {p.property_type && (
            <span className="type-badge">{fmtLabel(p.property_type)}</span>
          )}
        </div>

        <div className="card-body">
          <div className="card-price">{fmtPrice(p.price)}</div>
          <div className="card-title">{p.title || p.address}</div>
          <div className="card-addr">{p.address}</div>

          <div className="card-stats">
            {p.bedrooms  != null && <span>🛏 {p.bedrooms} bed</span>}
            {p.bathrooms != null && <span>🚿 {p.bathrooms} bath</span>}
          </div>

          <div className="score-row">
            <Chip
              icon="🚂"
              text={`${e.commuteMin}m`}
              tip={`${e.commuteMin} min to ${destination}`}
              clr={e.commuteMin <= 30 ? '#83B366' : e.commuteMin <= 50 ? '#DC8236' : '#B8210F'}
            />
            <Chip
              icon="🏫"
              text={e.schoolRating === 'Requires Improvement' ? 'Needs imp.' : e.schoolRating}
              tip="Nearest school Ofsted rating"
              clr={SCHOOL_CLR[e.schoolRating]}
            />
            <Chip
              icon="🛡"
              text={e.crimeLevel}
              tip="Local crime level"
              clr={CRIME_CLR[e.crimeLevel]}
            />
            <Chip
              icon="🚶"
              text={String(e.walkScore)}
              tip="Walk score out of 100"
              clr={e.walkScore >= 65 ? '#83B366' : e.walkScore >= 45 ? '#DC8236' : '#B8210F'}
            />
            <Chip
              icon="🌊"
              text={e.floodRisk === 'Very Low' ? 'Very low' : e.floodRisk}
              tip="Flood risk"
              clr={FLOOD_CLR[e.floodRisk]}
            />
          </div>

          <div className="card-footer">
            <span className="footer-tag">🏠 {e.nearestStationName} {e.nearestStationMi}mi</span>
            <span className="footer-tag">📶 {e.broadbandMbps}Mb</span>
          </div>
        </div>
      </a>
    </article>
  )
}

function Chip({ icon, text, tip, clr }: { icon: string; text: string; tip: string; clr: string }) {
  return (
    <span className="chip" title={tip} style={{ '--c': clr } as React.CSSProperties}>
      {icon} {text}
    </span>
  )
}
