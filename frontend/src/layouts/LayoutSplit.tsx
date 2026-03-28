import { useState, useRef, useEffect, useMemo } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import type { Property } from '../types/property'
import type { Filters } from '../App'
import type { MapBounds } from '../hooks/useProperties'
import './layouts.css'
import '../App.css'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon   from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
delete (L.Icon.Default.prototype as any)._getIconUrl
L.Icon.Default.mergeOptions({ iconRetinaUrl: markerIcon2x, iconUrl: markerIcon, shadowUrl: markerShadow })

function fmtPrice(pence: number) {
  return '£' + Math.round(pence / 100).toLocaleString('en-GB')
}
function fmtLabel(s: string) {
  return s.replace(/_/g, '-').replace(/\b\w/g, c => c.toUpperCase())
}

// Stable icon instances — creating new objects on every render causes Leaflet to flicker
const pinDefault = L.divIcon({
  className: '',
  html: `<svg width="24" height="32" viewBox="0 0 28 36" fill="none" xmlns="http://www.w3.org/2000/svg">
    <path d="M14 0C6.268 0 0 6.268 0 14c0 9.333 14 22 14 22S28 23.333 28 14C28 6.268 21.732 0 14 0z" fill="#E76814"/>
    <path d="M14 7C14 7 9 13 9 17.5a5 5 0 0010 0C19 13 14 7 14 7z" fill="#fff" opacity="0.9"/>
    <path d="M14 12C14 12 12 15 12 17.5a2 2 0 004 0C16 15 14 12 14 12z" fill="#891A10"/>
  </svg>`,
  iconSize: [24, 32],
  iconAnchor: [12, 32],
  popupAnchor: [0, -32],
})

function MapResizer() {
  const map = useMap()
  useEffect(() => {
    map.invalidateSize()
    const observer = new ResizeObserver(() => map.invalidateSize())
    observer.observe(map.getContainer())
    return () => observer.disconnect()
  }, [map])
  return null
}

function MapBoundsTracker({ onChange }: { onChange: (b: MapBounds) => void }) {
  const map = useMap()

  const emit = () => {
    const b = map.getBounds()
    onChange({
      sw_lat: b.getSouth(),
      sw_lng: b.getWest(),
      ne_lat: b.getNorth(),
      ne_lng: b.getEast(),
    })
  }

  useEffect(() => { emit() }, [map])
  useMapEvents({ moveend: emit, zoomend: emit })
  return null
}

const pinActive = L.divIcon({
  className: '',
  html: `<svg width="28" height="36" viewBox="0 0 28 36" fill="none" xmlns="http://www.w3.org/2000/svg">
    <path d="M14 0C6.268 0 0 6.268 0 14c0 9.333 14 22 14 22S28 23.333 28 14C28 6.268 21.732 0 14 0z" fill="#891A10"/>
    <path d="M14 7C14 7 9 13 9 17.5a5 5 0 0010 0C19 13 14 7 14 7z" fill="#fff" opacity="0.9"/>
    <path d="M14 12C14 12 12 15 12 17.5a2 2 0 004 0C16 15 14 12 14 12z" fill="#E76814"/>
  </svg>`,
  iconSize: [28, 36],
  iconAnchor: [14, 36],
  popupAnchor: [0, -36],
})

interface Props {
  properties: Property[]
  total: number
  filtered: Property[]
  filters: Filters
  sort: string
  setF: <K extends keyof Filters>(k: K, v: Filters[K]) => void
  toggleType: (t: string) => void
  setFilters: (f: Filters) => void
  setSort: (s: string) => void
  onBoundsChange: (b: MapBounds) => void
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '' }

const STATION_MINUTE_OPTIONS = [
  { value: 0,  label: 'Any' },
  { value: 5,  label: '5 min' },
  { value: 10, label: '10 min' },
  { value: 15, label: '15 min' },
  { value: 20, label: '20 min' },
  { value: 30, label: '30 min' },
]

const PROPERTY_TYPES = [
  { id: 'flat',          label: 'Flat' },
  { id: 'terraced',      label: 'Terraced' },
  { id: 'semi_detached', label: 'Semi' },
  { id: 'detached',      label: 'Detached' },
  { id: 'bungalow',      label: 'Bungalow' },
  { id: 'land',          label: 'Land' },
]

export default function LayoutSplit({
  filtered, filters, sort, setF, toggleType, setFilters, setSort, properties, total, onBoundsChange,
}: Props) {
  const [hoveredId, setHoveredId]     = useState<number | null>(null)
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const rowRefs = useRef<Record<number, HTMLAnchorElement | null>>({})

  const crimeRange = useMemo(() => {
    const rates = properties
      .map(p => p.crime?.avg_monthly_crimes)
      .filter((v): v is number => v != null)
    if (rates.length === 0) return null
    return { min: Math.floor(Math.min(...rates)), max: Math.ceil(Math.max(...rates)) }
  }, [properties])

  const mapItems = filtered.filter(p => p.latitude != null && p.longitude != null)

  return (
    <div className="l2-shell">
      {/* Sidebar */}
      <div className={`l2-sidebar ${sidebarOpen ? '' : 'l2-sidebar-collapsed'}`}>
        <button
          className="l2-sb-toggle"
          onClick={() => setSidebarOpen(o => !o)}
          title={sidebarOpen ? 'Hide filters' : 'Show filters'}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path
              d={sidebarOpen
                ? 'M9 2L4 7l5 5'
                : 'M5 2l5 5-5 5'}
              stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
            />
          </svg>
          {sidebarOpen && <span>Filters</span>}
        </button>

        {sidebarOpen && <div className="l2-sb-body">

        <div className="l2-sb-section">
          <span className="l2-sb-label">Sort</span>
          <select className="l2-sb-select" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="newest">Newest first</option>
            <option value="price_asc">Price: low to high</option>
            <option value="price_desc">Price: high to low</option>
            <option value="beds_asc">Fewest beds</option>
            <option value="beds_desc">Most beds</option>
          </select>
        </div>

        <div className="l2-sb-section">
          <span className="l2-sb-label">Price</span>
          <div className="l2-sb-row">
            <input
              className="l2-sb-input"
              type="number"
              placeholder="Min £"
              value={filters.minPrice}
              onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)}
            />
            <span style={{ color: 'var(--t4)', fontSize: '0.75rem', flexShrink: 0 }}>—</span>
            <input
              className="l2-sb-input"
              type="number"
              placeholder="Max £"
              value={filters.maxPrice}
              onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)}
            />
          </div>
        </div>

        <div className="l2-sb-section">
          <span className="l2-sb-label">Min bedrooms</span>
          <div className="l2-sb-pills">
            {[0, 1, 2, 3, 4, 5].map(n => (
              <button
                key={n}
                className={`l2-sb-pill ${filters.minBeds === n ? 'on' : ''}`}
                onClick={() => setF('minBeds', n)}
              >{n === 0 ? 'Any' : `${n}+`}</button>
            ))}
          </div>
        </div>

        <div className="l2-sb-section">
          <span className="l2-sb-label">Property type</span>
          <div className="l2-sb-chips">
            {PROPERTY_TYPES.map(t => (
              <button
                key={t.id}
                className={`l2-sb-chip ${filters.types.includes(t.id) ? 'on' : ''}`}
                onClick={() => toggleType(t.id)}
              >{t.label}</button>
            ))}
          </div>
          {filters.types.length === 0 && <p className="l2-sb-hint">All types shown</p>}
        </div>

        {crimeRange && (
        <div className="l2-sb-section">
          <div className="l2-sb-slider-header">
            <span className="l2-sb-label" style={{ marginBottom: 0 }}>Crime rate</span>
            <span className="l2-sb-slider-value">
              {filters.maxCrimeRate === '' || filters.maxCrimeRate === crimeRange.max
                ? 'Any'
                : `up to ${Math.round(filters.maxCrimeRate as number)}/mo`}
            </span>
          </div>
          {(() => {
            const val = filters.maxCrimeRate === '' ? crimeRange.max : filters.maxCrimeRate as number
            const pct = Math.round(((val - crimeRange.min) / (crimeRange.max - crimeRange.min)) * 100)
            return (
              <input
                className="l2-sb-slider"
                type="range"
                min={crimeRange.min}
                max={crimeRange.max}
                step={1}
                value={val}
                style={{ '--slider-pct': pct } as React.CSSProperties}
                onChange={e => {
                  const v = +e.target.value
                  setF('maxCrimeRate', v >= crimeRange.max ? '' : v)
                }}
              />
            )
          })()}
          <div className="l2-sb-slider-range">
            <span>{crimeRange.min}</span>
            <span>{crimeRange.max} crimes/mo</span>
          </div>
        </div>
        )}

        <div className="l2-sb-section">
          <span className="l2-sb-label">Walk to station</span>
          <div className="l2-sb-pills">
            {STATION_MINUTE_OPTIONS.map(opt => (
              <button
                key={opt.value}
                className={`l2-sb-pill ${filters.maxStationMinutes === opt.value ? 'on' : ''}`}
                onClick={() => setF('maxStationMinutes', opt.value)}
              >{opt.label}</button>
            ))}
          </div>
        </div>

        <div className="l2-sb-section">
          <button className="l2-sb-reset" onClick={() => setFilters(INIT)}>
            Reset filters
          </button>
        </div>

        </div>}

      </div>

      {/* List panel */}
      <div className="l2-left">
        <div className="l2-count">
          {filtered.length.toLocaleString()} of {total.toLocaleString()} homes in view
          {total > properties.length && (
            <span className="l2-count-hint"> &mdash; showing first {properties.length.toLocaleString()}, zoom in to see more</span>
          )}
        </div>

        <div className="l2-list">
          {filtered.map(p => (
            <a
              key={p.id}
              ref={el => { rowRefs.current[p.id] = el }}
              href={`https://www.rightmove.co.uk/properties/${p.rightmove_id}`}
              target="_blank"
              rel="noreferrer"
              className={`l2-row ${hoveredId === p.id ? 'l2-active' : ''}`}
              onMouseEnter={() => setHoveredId(p.id)}
              onMouseLeave={() => setHoveredId(null)}
            >
              <div className="l2-thumb">
                {p.photo_url
                  ? <img src={p.photo_url} alt="" loading="lazy" />
                  : <div className="l2-thumb-ph" />
                }
              </div>
              <div className="l2-details">
                <div className="l2-price">{fmtPrice(p.price)}</div>
                <div className="l2-title">{p.title || p.address}</div>
                <div className="l2-addr">{p.address}</div>
                <div className="l2-stats">
                  {p.bedrooms  != null && <span>{p.bedrooms} bed</span>}
                  {p.bathrooms != null && <span>{p.bathrooms} bath</span>}
                </div>
                {p.nearest_stations?.length > 0 && (() => {
                  const s = p.nearest_stations[0]
                  return <div className="l2-station">{s.walking_minutes} min walk · {s.name}</div>
                })()}
              </div>
              {p.property_type && (
                <span className="l2-badge">{p.property_type === 'semi_detached' ? 'Semi' : fmtLabel(p.property_type)}</span>
              )}
            </a>
          ))}
          {filtered.length === 0 && (
            <div className="l2-empty">
              <span>Nothing matches your search just yet.</span>
              <button
                className="reset-btn"
                style={{ display: 'inline-block', width: 'auto', marginTop: 4, padding: '6px 16px', fontStyle: 'normal', fontFamily: 'var(--ff-body)', fontSize: '0.8rem' }}
                onClick={() => setFilters(INIT)}
              >
                Clear filters
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Map */}
      <div className="l2-map">
        <MapContainer center={[51.38, -2.36]} zoom={11} style={{ height: '100%', width: '100%' }}>
          <MapResizer />
          <MapBoundsTracker onChange={onBoundsChange} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>'
            url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
          />
          {mapItems.map(p => (
            <Marker
              key={p.id}
              position={[p.latitude, p.longitude]}
              icon={hoveredId === p.id ? pinActive : pinDefault}
              eventHandlers={{
                mouseover: () => setHoveredId(p.id),
                mouseout: () => setHoveredId(null),
              }}
            >
              <Popup>
                <div className="map-popup">
                  <div className="map-popup-price">{fmtPrice(p.price)}</div>
                  <div className="map-popup-title">{p.title || p.address}</div>
                  {(p.bedrooms != null || p.bathrooms != null) && (
                    <div className="map-popup-stats">
                      {p.bedrooms != null && `${p.bedrooms} bed`}
                      {p.bedrooms != null && p.bathrooms != null && ' · '}
                      {p.bathrooms != null && `${p.bathrooms} bath`}
                    </div>
                  )}
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>
    </div>
  )
}
