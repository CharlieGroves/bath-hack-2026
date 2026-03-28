import { useState, useRef, useEffect, useMemo } from 'react'
import { MapContainer, TileLayer, Marker, Popup, Polygon, useMap, useMapEvents } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import 'leaflet.heat'
import L from 'leaflet'
import LocationAutocompleteInput from '../components/LocationAutocompleteInput'
import type { BoundingBox, IsochronePoint, Property } from '../types/property'
import type { Filters } from '../App'
import type { ActiveLocationSearch, LocationSearchParams, MapBounds, TransportationType } from '../hooks/useProperties'
import { useHeatmapData } from '../hooks/useHeatmapData'
import './layouts.css'
import '../App.css'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon   from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'
type LeafletDefaultIconPrototype = { _getIconUrl?: string }

delete (L.Icon.Default.prototype as LeafletDefaultIconPrototype)._getIconUrl
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

type MapLayer = 'markers' | 'heatmap'

function HeatmapLayer({ points }: { points: [number, number, number][] }) {
  const map = useMap()

  useEffect(() => {
    if (!points.length) return
    const layer = L.heatLayer(points, {
      radius: 25,
      blur: 18,
      maxZoom: 17,
      max: 0.12,
      gradient: { 0.0: '#3b82f6', 0.5: '#f59e0b', 1.0: '#dc2626' },
    })
    layer.addTo(map)
    return () => { layer.remove() }
  }, [map, points])

  return null
}

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

  useEffect(() => {
    const bounds = map.getBounds()
    onChange({
      sw_lat: bounds.getSouth(),
      sw_lng: bounds.getWest(),
      ne_lat: bounds.getNorth(),
      ne_lng: bounds.getEast(),
    })
  }, [map, onChange])

  useMapEvents({
    moveend() {
      const bounds = map.getBounds()
      onChange({
        sw_lat: bounds.getSouth(),
        sw_lng: bounds.getWest(),
        ne_lat: bounds.getNorth(),
        ne_lng: bounds.getEast(),
      })
    },
    zoomend() {
      const bounds = map.getBounds()
      onChange({
        sw_lat: bounds.getSouth(),
        sw_lng: bounds.getWest(),
        ne_lat: bounds.getNorth(),
        ne_lng: bounds.getEast(),
      })
    },
  })
  return null
}

function leafletBoundsFromBoundingBox(boundingBox: BoundingBox) {
  return [
    [boundingBox.south, boundingBox.west],
    [boundingBox.north, boundingBox.east],
  ] as [[number, number], [number, number]]
}

function shellToLeafletLatLngs(shell: IsochronePoint[]) {
  return shell.map(point => [point.latitude, point.longitude] as [number, number])
}

function SearchIsochrone({ shells }: { shells: IsochronePoint[][] }) {
  if (shells.length === 0) return null

  return (
    <>
      {shells.map((shell, index) => (
        <Polygon
          key={index}
          positions={shellToLeafletLatLngs(shell)}
          pathOptions={{
            color: '#E76814',
            weight: 2,
            opacity: 0.95,
            fillColor: '#E76814',
            fillOpacity: 0.09,
          }}
        />
      ))}
    </>
  )
}

function MapSearchFitBounds({ boundingBox }: { boundingBox: BoundingBox | null }) {
  const map = useMap()
  const north = boundingBox?.north
  const south = boundingBox?.south
  const east = boundingBox?.east
  const west = boundingBox?.west

  useEffect(() => {
    if (north == null || south == null || east == null || west == null) return

    map.fitBounds(leafletBoundsFromBoundingBox({ north, south, east, west }), {
      padding: [28, 28],
      maxZoom: 13,
    })
  }, [map, north, south, east, west])

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
  loading: boolean
  filtered: Property[]
  filters: Filters
  sort: string
  setF: <K extends keyof Filters>(k: K, v: Filters[K]) => void
  toggleType: (t: string) => void
  setFilters: (f: Filters) => void
  setSort: (s: string) => void
  onBoundsChange: (b: MapBounds) => void
  onSelectProperty: (id: number) => void
  viewportError: string | null
  locationSearchError: string | null
  locationSearchLoading: boolean
  locationSearch: LocationSearchParams
  activeLocationSearch: ActiveLocationSearch | null
  onLocationQueryChange: (value: string) => void
  onTransportationTypeChange: (value: TransportationType) => void
  onTravelTimeMinutesChange: (value: number) => void
  onApplyLocationSearch: () => void
  onClearLocationSearch: () => void
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '', minPricePerSqft: '', maxPricePerSqft: '', maxDaqi: 0, minFloodRisk: 0, maxFloodRisk: 0 }

const FLOOD_RISK_LABELS: Record<number, string> = { 1: 'Very Low', 2: 'Low', 3: 'Medium', 4: 'High' }

const STATION_MINUTE_OPTIONS = [
  { value: 0,  label: 'Any' },
  { value: 5,  label: '5 min' },
  { value: 10, label: '10 min' },
  { value: 15, label: '15 min' },
  { value: 20, label: '20 min' },
  { value: 30, label: '30 min' },
]

const TRANSPORTATION_OPTIONS: { value: TransportationType; label: string }[] = [
  { value: 'driving', label: 'Driving' },
  { value: 'walking', label: 'Walking' },
  { value: 'cycling', label: 'Cycling' },
  { value: 'public_transport', label: 'Public transport' },
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
  filtered,
  filters,
  sort,
  setF,
  toggleType,
  setFilters,
  setSort,
  properties,
  total,
  loading,
  onBoundsChange,
  onSelectProperty,
  viewportError,
  locationSearchError,
  locationSearchLoading,
  locationSearch,
  activeLocationSearch,
  onLocationQueryChange,
  onTransportationTypeChange,
  onTravelTimeMinutesChange,
  onApplyLocationSearch,
  onClearLocationSearch,
}: Props) {
  const [hoveredId, setHoveredId]     = useState<number | null>(null)
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [mapLayer, setMapLayer]       = useState<MapLayer>('markers')
  const { points: heatmapPoints, minPricePerSqft, maxPricePerSqft } = useHeatmapData()
  const rowRefs = useRef<Record<number, HTMLDivElement | null>>({})

  const crimeRange = useMemo(() => {
    const rates = properties
      .map(p => p.crime?.avg_monthly_crimes)
      .filter((v): v is number => v != null)
    if (rates.length === 0) return null
    return { min: Math.floor(Math.min(...rates)), max: Math.ceil(Math.max(...rates)) }
  }, [properties])

  const mapItems = filtered.filter(p => p.latitude != null && p.longitude != null)
  const locationSearchHint = activeLocationSearch
    ? `${activeLocationSearch.travelTimeMinutes} min ${fmtLabel(activeLocationSearch.transportationType)} from ${activeLocationSearch.location.label}`
    : null

  return (
    <div className="l2-shell">
      {/* Sidebar */}
      <div className={`l2-sidebar ${sidebarOpen ? '' : 'l2-sidebar-collapsed'}`}>
        <button
          type="button"
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
          <span className="l2-sb-label">Distance from place</span>
          <LocationAutocompleteInput
            value={locationSearch.query}
            onChange={onLocationQueryChange}
            onEnter={onApplyLocationSearch}
            inputClassName="l2-sb-text-input"
            placeholder="King's Cross, SW1A 1AA, Canary Wharf..."
          />
          <div className="l2-sb-search-grid">
            <select
              className="l2-sb-select"
              value={locationSearch.transportationType}
              onChange={e => onTransportationTypeChange(e.target.value as TransportationType)}
            >
              {TRANSPORTATION_OPTIONS.map(option => (
                <option key={option.value} value={option.value}>{option.label}</option>
              ))}
            </select>
            <input
              className="l2-sb-input"
              type="number"
              min={1}
              max={120}
              step={1}
              inputMode="numeric"
              placeholder="Minutes"
              value={locationSearch.travelTimeMinutes}
              onChange={e => {
                const nextValue = Number(e.target.value)
                if (Number.isNaN(nextValue)) return
                onTravelTimeMinutesChange(Math.min(120, Math.max(1, nextValue)))
              }}
            />
          </div>
          <div className="l2-sb-actions">
            <button
              type="button"
              className="l2-sb-primary"
              onClick={() => onApplyLocationSearch()}
              disabled={!locationSearch.query.trim() || locationSearchLoading}
            >
              {locationSearchLoading ? 'Searching...' : 'Apply search'}
            </button>
            {activeLocationSearch && (
              <button type="button" className="l2-sb-secondary" onClick={onClearLocationSearch}>
                Clear
              </button>
            )}
          </div>
          {activeLocationSearch ? (
            <div className="l2-sb-search-state">
              <div className="l2-sb-search-title">{activeLocationSearch.location.label}</div>
              <div className="l2-sb-search-meta">
                {activeLocationSearch.travelTimeMinutes} min {fmtLabel(activeLocationSearch.transportationType)}
              </div>
              <div className="l2-sb-search-meta">Isochrone area shown on the map</div>
            </div>
          ) : (
            <p className="l2-sb-hint">Try a postcode, station, landmark, or neighborhood. Travel time accepts any whole minute from 1 to 120.</p>
          )}
          {locationSearchError && (
            <p className="l2-sb-error">{locationSearchError}</p>
          )}
        </div>

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
          <span className="l2-sb-label">Price per sq ft</span>
          <div className="l2-sb-row">
            <input
              className="l2-sb-input"
              type="number"
              placeholder="Min £"
              value={filters.minPricePerSqft}
              onChange={e => setF('minPricePerSqft', e.target.value === '' ? '' : +e.target.value)}
            />
            <span style={{ color: 'var(--t4)', fontSize: '0.75rem', flexShrink: 0 }}>—</span>
            <input
              className="l2-sb-input"
              type="number"
              placeholder="Max £"
              value={filters.maxPricePerSqft}
              onChange={e => setF('maxPricePerSqft', e.target.value === '' ? '' : +e.target.value)}
            />
          </div>
        </div>

        <div className="l2-sb-section">
          <span className="l2-sb-label">Min bedrooms</span>
          <div className="l2-sb-pills">
            {[0, 1, 2, 3, 4, 5].map(n => (
              <button
                type="button"
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
                type="button"
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
          <div className="l2-sb-slider-header">
            <span className="l2-sb-label" style={{ marginBottom: 0 }}>Air quality (DAQI)</span>
            <span className="l2-sb-slider-value">
              {filters.maxDaqi === 0 || filters.maxDaqi >= 5 ? 'Any' : `up to ${filters.maxDaqi}`}
            </span>
          </div>
          {(() => {
            const val = filters.maxDaqi === 0 ? 5 : filters.maxDaqi
            const pct = Math.round(((val - 1) / (5 - 1)) * 100)
            return (
              <input
                className="l2-sb-slider"
                type="range"
                min={1}
                max={5}
                step={1}
                value={val}
                style={{ '--slider-pct': pct } as React.CSSProperties}
                onChange={e => {
                  const v = +e.target.value
                  setF('maxDaqi', v >= 5 ? 0 : v)
                }}
              />
            )
          })()}
          <div className="l2-sb-slider-range">
            <span>1 (cleanest)</span>
            <span>5 (moderate)</span>
          </div>
        </div>

        <div className="l2-sb-section">
          <span className="l2-sb-label">Walk to station</span>
          <div className="l2-sb-pills">
            {STATION_MINUTE_OPTIONS.map(opt => (
              <button
                type="button"
                key={opt.value}
                className={`l2-sb-pill ${filters.maxStationMinutes === opt.value ? 'on' : ''}`}
                onClick={() => setF('maxStationMinutes', opt.value)}
              >{opt.label}</button>
            ))}
          </div>
        </div>

        <div className="l2-sb-section">
          {(() => {
            const minVal = filters.minFloodRisk === 0 ? 1 : filters.minFloodRisk
            const maxVal = filters.maxFloodRisk === 0 ? 4 : filters.maxFloodRisk
            const isDefault = filters.minFloodRisk === 0 && filters.maxFloodRisk === 0
            const minPct = Math.round(((minVal - 1) / 3) * 100)
            const maxPct = Math.round(((maxVal - 1) / 3) * 100)
            return (
              <>
                <div className="l2-sb-slider-header">
                  <span className="l2-sb-label" style={{ marginBottom: 0 }}>Flood risk</span>
                  <span className="l2-sb-slider-value">
                    {isDefault ? 'Any' : minVal === maxVal ? FLOOD_RISK_LABELS[minVal] : `${FLOOD_RISK_LABELS[minVal]} — ${FLOOD_RISK_LABELS[maxVal]}`}
                  </span>
                </div>
                <div className="l2-sb-dual-slider">
                  <div
                    className="l2-sb-dual-track"
                    style={{ '--min-pct': minPct, '--max-pct': maxPct } as React.CSSProperties}
                  />
                  <input
                    className="l2-sb-range"
                    type="range" min={1} max={4} step={1} value={minVal}
                    onChange={e => {
                      const v = +e.target.value
                      const newMax = Math.max(v, maxVal)
                      setF('minFloodRisk', v === 1 && newMax === 4 ? 0 : v)
                      setF('maxFloodRisk', v === 1 && newMax === 4 ? 0 : newMax)
                    }}
                  />
                  <input
                    className="l2-sb-range"
                    type="range" min={1} max={4} step={1} value={maxVal}
                    onChange={e => {
                      const v = +e.target.value
                      const newMin = Math.min(minVal, v)
                      setF('minFloodRisk', newMin === 1 && v === 4 ? 0 : newMin)
                      setF('maxFloodRisk', newMin === 1 && v === 4 ? 0 : v)
                    }}
                  />
                </div>
                <div className="l2-sb-slider-range">
                  <span>Very Low</span>
                  <span>High</span>
                </div>
              </>
            )
          })()}
        </div>

        <div className="l2-sb-section">
          <button type="button" className="l2-sb-reset" onClick={() => setFilters(INIT)}>
            Reset filters
          </button>
        </div>

        </div>}

      </div>

      {/* List panel */}
      <div className="l2-left">
        <div className="l2-count">
          {activeLocationSearch
            ? `${filtered.length.toLocaleString()} of ${total.toLocaleString()} homes matching ${locationSearchHint}`
            : `${filtered.length.toLocaleString()} of ${total.toLocaleString()} homes in view`}
          {loading && (
            <span className="l2-count-status">
              {activeLocationSearch ? ' Updating search...' : ' Loading homes...'}
            </span>
          )}
          {total > properties.length && (
            <span className="l2-count-hint"> &mdash; showing first {properties.length.toLocaleString()}, zoom in to see more</span>
          )}
          {viewportError && (
            <div className="l2-count-error">{viewportError}</div>
          )}
        </div>

        <div className="l2-list">
          {filtered.map(p => (
            <div
              key={p.id}
              ref={el => { rowRefs.current[p.id] = el }}
              className={`l2-row ${hoveredId === p.id ? 'l2-active' : ''}`}
              onMouseEnter={() => setHoveredId(p.id)}
              onMouseLeave={() => setHoveredId(null)}
              onClick={() => onSelectProperty(p.id)}
              style={{ cursor: 'pointer' }}
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
            </div>
          ))}
          {filtered.length === 0 && (
            <div className="l2-empty">
              <span>Nothing matches your search just yet.</span>
              <button
                type="button"
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
        {mapLayer === 'heatmap' && (
          <div className="l2-heatmap-key">
            <div className="l2-heatmap-key-bar" />
            <div className="l2-heatmap-key-labels">
              <span>{minPricePerSqft != null ? `£${minPricePerSqft.toLocaleString('en-GB')}` : '—'}</span>
              <span className="l2-heatmap-key-title">price / sq ft</span>
              <span>{maxPricePerSqft != null ? `£${maxPricePerSqft.toLocaleString('en-GB')}` : '—'}</span>
            </div>
          </div>
        )}
        <div className="l2-layer-toggle">
          <button
            type="button"
            className={mapLayer === 'markers' ? 'on' : ''}
            onClick={() => setMapLayer('markers')}
          >Markers</button>
          <button
            type="button"
            className={mapLayer === 'heatmap' ? 'on' : ''}
            onClick={() => setMapLayer('heatmap')}
          >Price / sq ft</button>
        </div>
        <MapContainer center={[51.5074, -0.1278]} zoom={11} style={{ height: '100%', width: '100%' }}>
          <MapResizer />
          <MapBoundsTracker onChange={onBoundsChange} />
          <MapSearchFitBounds boundingBox={activeLocationSearch?.boundingBox ?? null} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>'
            url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
          />
          <SearchIsochrone shells={activeLocationSearch?.isochroneShells ?? []} />
          {mapLayer === 'heatmap' && <HeatmapLayer points={heatmapPoints} />}
          {mapLayer === 'markers' && mapItems.map(p => (
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
                <div className="map-popup" onClick={() => onSelectProperty(p.id)} style={{ cursor: 'pointer' }}>
                  <div className="map-popup-price">{fmtPrice(p.price)}</div>
                  <div className="map-popup-title">{p.title || p.address}</div>
                  {(p.bedrooms != null || p.bathrooms != null) && (
                    <div className="map-popup-stats">
                      {p.bedrooms != null && `${p.bedrooms} bed`}
                      {p.bedrooms != null && p.bathrooms != null && ' · '}
                      {p.bathrooms != null && `${p.bathrooms} bath`}
                    </div>
                  )}
                  <div className="map-popup-cta">View property</div>
                </div>
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>
    </div>
  )
}
