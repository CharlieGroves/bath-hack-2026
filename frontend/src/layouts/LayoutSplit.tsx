import { useState, useRef, useEffect } from 'react'
import { MapContainer, TileLayer, WMSTileLayer, Marker, Popup, Polygon, useMap, useMapEvents } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import 'leaflet.heat'
import L from 'leaflet'
import type { BoundingBox, IsochronePoint, Property } from '../types/property'
import type { Filters } from '../App'
import type { ActiveLocationSearch, LocationSearchParams, MapBounds, TransportationType } from '../hooks/useProperties'
import LocationAutocompleteInput from '../components/LocationAutocompleteInput'
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
function fmtPriceShort(pence: number) {
  const pounds = Math.round(pence / 100)
  if (pounds >= 1_000_000) return `£${(pounds / 1_000_000).toFixed(pounds % 1_000_000 === 0 ? 0 : 1)}m`
  if (pounds >= 1_000) return `£${Math.round(pounds / 1_000)}k`
  return `£${pounds}`
}

function makePriceIcon(price: number, active: boolean) {
  return L.divIcon({
    className: '',
    html: `<div class="price-marker${active ? ' price-marker--active' : ''}">${fmtPriceShort(price)}</div>`,
    iconAnchor: [0, 0],
    popupAnchor: [0, -8],
  })
}

type MapLayer = 'markers' | 'heatmap' | 'noise_road' | 'noise_rail' | 'noise_flight'

const NOISE_WMS_LAYERS: Record<'noise_road' | 'noise_rail' | 'noise_flight', { url: string; layers: string; label: string }> = {
  noise_road: {
    url: 'https://environment.data.gov.uk/geoservices/datasets/562c9d56-7c2d-4d42-83bb-578d6e97a517/wms',
    layers: 'Road_Noise_Lden_England_Round_4_All',
    label: 'Road noise',
  },
  noise_rail: {
    url: 'https://environment.data.gov.uk/geoservices/datasets/3fb3c2d7-292c-4e0a-bd5b-d8e4e1fe2947/wms',
    layers: 'Rail_Noise_Lden_England_Round_4_All',
    label: 'Rail noise',
  },
  noise_flight: {
    url: 'https://environment.data.gov.uk/geoservices/datasets/dac9cba4-abe7-43bd-b8e9-8a83da52edd8/wms',
    layers: 'Airport_Noise_ALL_Lden',
    label: 'Flight noise',
  },
}

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


interface Props {
  properties: Property[]  // used for "showing first N" hint
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
  activeLocationSearch: ActiveLocationSearch | null
  locationSearchDraft: LocationSearchParams
  onLocationSearchFieldChange: <K extends keyof LocationSearchParams>(key: K, value: LocationSearchParams[K]) => void
  onApplyLocationSearch: (queryOverride?: string) => boolean
  onClearLocationSearch: () => void
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '', minPricePerSqft: '', maxPricePerSqft: '', maxDaqi: 0, minFloodRisk: 0, maxFloodRisk: 0, maxRoadNoiseLden: '', maxRailNoiseLden: '', maxFlightNoiseLden: '', minAgentRating: '', sharedOwnershipFilter: 'exclude' }

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
  filtered,
  filters,
  sort,
  setF,
  setFilters,
  setSort,
  properties,
  total,
  loading,
  onBoundsChange,
  onSelectProperty,
  viewportError,
  activeLocationSearch,
  locationSearchDraft,
  onLocationSearchFieldChange,
  onApplyLocationSearch,
  onClearLocationSearch,
}: Props) {
  const [hoveredId, setHoveredId]       = useState<number | null>(null)
  const [expandedRows, setExpandedRows] = useState<Set<number>>(new Set())
  const [filtersOpen, setFiltersOpen]   = useState(false)
  const [mapLayer, setMapLayer]         = useState<MapLayer>('markers')
  const { points: heatmapPoints, minPricePerSqft, maxPricePerSqft } = useHeatmapData()
  const rowRefs = useRef<Record<number, HTMLDivElement | null>>({})


  const mapItems = filtered.filter(p => p.latitude != null && p.longitude != null)
  const locationSearchHint = activeLocationSearch
    ? `${activeLocationSearch.travelTimeMinutes} min ${fmtLabel(activeLocationSearch.transportationType)} from ${activeLocationSearch.location.label}`
    : null


  return (
    <div className="l2-shell">
      <div className="l2-filterbar">
        <button type="button" className={`l2-fb-toggle${filtersOpen ? ' on' : ''}`} onClick={() => setFiltersOpen(o => !o)}>
          Filters
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d={filtersOpen ? 'M2 7l3-3 3 3' : 'M2 3l3 3 3-3'} stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        <div className="l2-fb-right">
          <span className="l2-fb-count">{filtered.length.toLocaleString()} of {total.toLocaleString()}</span>
          <select className="l2-fb-sort" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="newest">Newest</option>
            <option value="price_asc">Price low–high</option>
            <option value="price_desc">Price high–low</option>
            <option value="beds_asc">Fewest beds</option>
            <option value="beds_desc">Most beds</option>
          </select>
        </div>
      </div>

      {filtersOpen && (
        <div className="l2-fb-panel">
          <div className="l2-fb-row">
            <span className="l2-fb-label">Price</span>
            <input className="l2-fb-input" type="number" placeholder="Min £" value={filters.minPrice} onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)} />
            <span className="l2-fb-dash">—</span>
            <input className="l2-fb-input" type="number" placeholder="Max £" value={filters.maxPrice} onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)} />
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Beds</span>
            <select className="l2-fb-select"
              value={filters.minBeds}
              onChange={e => setF('minBeds', +e.target.value)}
            >
              <option value={0}>Any</option>
              {[1,2,3,4,5].map(n => <option key={n} value={n}>{n}+</option>)}
            </select>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Type</span>
            <select className="l2-fb-select"
              value={filters.types[0] ?? ''}
              onChange={e => setF('types', e.target.value === '' ? [] : [e.target.value])}
            >
              <option value="">Any</option>
              {PROPERTY_TYPES.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
            </select>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Station</span>
            <select className="l2-fb-select"
              value={filters.maxStationMinutes}
              onChange={e => setF('maxStationMinutes', +e.target.value)}
            >
              {STATION_MINUTE_OPTIONS.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)}
            </select>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Agent</span>
            <select className="l2-fb-select"
              value={filters.minAgentRating}
              onChange={e => setF('minAgentRating', e.target.value === '' ? '' : +e.target.value)}
            >
              <option value="">Any</option>
              {[3, 3.5, 4, 4.5].map(v => <option key={v} value={v}>{v}+</option>)}
            </select>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Ownership</span>
            <select
              className="l2-fb-select"
              value={filters.sharedOwnershipFilter}
              onChange={e => setF('sharedOwnershipFilter', e.target.value as Filters['sharedOwnershipFilter'])}
            >
              <option value="exclude">No % share</option>
              <option value="any">Any</option>
              <option value="only">% share only</option>
            </select>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Crime rate</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={250} max={3750} step={250}
                value={filters.maxCrimeRate === '' ? 3750 : (filters.maxCrimeRate as number)}
                onChange={e => { const v = +e.target.value; setF('maxCrimeRate', v === 3750 ? '' : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxCrimeRate === '' ? 'Any' : `${(filters.maxCrimeRate as number).toLocaleString()}/mo`}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Air pollution</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={1} max={11} step={1}
                value={filters.maxDaqi === 0 ? 11 : filters.maxDaqi}
                onChange={e => { const v = +e.target.value; setF('maxDaqi', v === 11 ? 0 : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxDaqi === 0 ? 'Any' : `DAQI ${filters.maxDaqi}`}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Road noise</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={40} max={80} step={5}
                value={filters.maxRoadNoiseLden === '' ? 80 : (filters.maxRoadNoiseLden as number)}
                onChange={e => { const v = +e.target.value; setF('maxRoadNoiseLden', v === 80 ? '' : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxRoadNoiseLden === '' ? 'Any' : `${filters.maxRoadNoiseLden} dB`}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Rail noise</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={40} max={80} step={5}
                value={filters.maxRailNoiseLden === '' ? 80 : (filters.maxRailNoiseLden as number)}
                onChange={e => { const v = +e.target.value; setF('maxRailNoiseLden', v === 80 ? '' : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxRailNoiseLden === '' ? 'Any' : `${filters.maxRailNoiseLden} dB`}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Flight noise</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={40} max={80} step={5}
                value={filters.maxFlightNoiseLden === '' ? 80 : (filters.maxFlightNoiseLden as number)}
                onChange={e => { const v = +e.target.value; setF('maxFlightNoiseLden', v === 80 ? '' : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxFlightNoiseLden === '' ? 'Any' : `${filters.maxFlightNoiseLden} dB`}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row">
            <span className="l2-fb-label">Flood risk</span>
            <div className="l2-fb-slider-row">
              <input type="range" min={1} max={5} step={1}
                value={filters.maxFloodRisk === 0 ? 5 : filters.maxFloodRisk}
                onChange={e => { const v = +e.target.value; setF('maxFloodRisk', v === 5 ? 0 : v) }}
              />
              <span className="l2-fb-slider-val">
                {filters.maxFloodRisk === 0 ? 'Any' : ['Very Low', 'Low', 'Medium', 'High'][filters.maxFloodRisk - 1]}
              </span>
              <span className="l2-fb-slider-dir">lower = better</span>
            </div>
          </div>

          <div className="l2-fb-row l2-fb-row--full">
            <span className="l2-fb-label">Distance to</span>
            <LocationAutocompleteInput
              value={locationSearchDraft.query}
              onChange={q => onLocationSearchFieldChange('query', q)}
              onSelect={suggestion => onApplyLocationSearch(suggestion.label)}
              onEnter={() => { if (locationSearchDraft.query.trim()) onApplyLocationSearch() }}
              placeholder="Any location"
              inputClassName="l2-fb-input"
              wrapperClassName="l2-fb-location-wrap"
            />
            <select
              className="l2-fb-select"
              value={locationSearchDraft.transportationType}
              onChange={e => onLocationSearchFieldChange('transportationType', e.target.value as TransportationType)}
            >
              <option value="driving">Drive</option>
              <option value="walking">Walk</option>
              <option value="cycling">Cycle</option>
              <option value="public_transport">Transit</option>
            </select>
            <select
              className="l2-fb-select"
              value={locationSearchDraft.travelTimeMinutes}
              onChange={e => onLocationSearchFieldChange('travelTimeMinutes', +e.target.value)}
            >
              {[5, 10, 15, 20, 30, 45, 60].map(m => (
                <option key={m} value={m}>{m} min</option>
              ))}
            </select>
            {activeLocationSearch && (
              <button type="button" className="l2-fb-reset" onClick={onClearLocationSearch}>Clear</button>
            )}
          </div>

          <div className="l2-fb-row l2-fb-row--full">
            <button type="button" className="l2-fb-reset" onClick={() => setFilters(INIT)}>Reset all</button>
          </div>
        </div>
      )}

      <div className="l2-main">

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
          {filtered.map(p => {
            const expanded = expandedRows.has(p.id)
            function toggleExpand(e: React.MouseEvent) {
              e.stopPropagation()
              setExpandedRows(prev => {
                const next = new Set(prev)
                next.has(p.id) ? next.delete(p.id) : next.add(p.id)
                return next
              })
            }
            return (
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
                {expanded && <>
                  <div className="l2-stats">
                    {p.bedrooms  != null && <span>{p.bedrooms} bed</span>}
                    {p.bathrooms != null && <span>{p.bathrooms} bath</span>}
                  </div>
                  {p.nearest_stations?.length > 0 && (() => {
                    const s = p.nearest_stations[0]
                    return <div className="l2-station">{s.walking_minutes} min walk · {s.name}</div>
                  })()}
                </>}
                <button type="button" className="l2-expand-btn" onClick={toggleExpand} title={expanded ? 'Show less' : 'Show more'}>
                  <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                    <path d={expanded ? 'M2 7l3-3 3 3' : 'M2 3l3 3 3-3'} stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
                  </svg>
                </button>
              </div>
            </div>
            )
          })}
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
          <button
            type="button"
            className={mapLayer === 'noise_road' ? 'on' : ''}
            onClick={() => setMapLayer('noise_road')}
          >Road noise</button>
          <button
            type="button"
            className={mapLayer === 'noise_rail' ? 'on' : ''}
            onClick={() => setMapLayer('noise_rail')}
          >Rail noise</button>
          <button
            type="button"
            className={mapLayer === 'noise_flight' ? 'on' : ''}
            onClick={() => setMapLayer('noise_flight')}
          >Flight noise</button>
        </div>
        <MapContainer center={[51.5074, -0.1278]} zoom={11} style={{ height: '100%', width: '100%' }}>
          <MapResizer />
          <MapBoundsTracker onChange={onBoundsChange} />
          <MapSearchFitBounds boundingBox={activeLocationSearch?.boundingBox ?? null} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
            url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
            subdomains="abcd"
            maxZoom={19}
          />
          <SearchIsochrone shells={activeLocationSearch?.isochroneShells ?? []} />
          {mapLayer === 'heatmap' && <HeatmapLayer points={heatmapPoints} />}
          {(mapLayer === 'noise_road' || mapLayer === 'noise_rail' || mapLayer === 'noise_flight') && (
            <WMSTileLayer
              key={mapLayer}
              url={NOISE_WMS_LAYERS[mapLayer].url}
              layers={NOISE_WMS_LAYERS[mapLayer].layers}
              format="image/png"
              transparent={true}
              opacity={0.75}
              attribution='&copy; <a href="https://environment.data.gov.uk">Environment Agency</a>'
            />
          )}
          {mapItems.map(p => (
            <Marker
              key={p.id}
              position={[p.latitude, p.longitude]}
              icon={makePriceIcon(p.price, hoveredId === p.id)}
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
    </div>
  )
}
