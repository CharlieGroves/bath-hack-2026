import { useState, useRef, useEffect } from 'react'
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import type { Property } from '../types/property'
import type { Filters } from '../App'
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
  useEffect(() => { map.invalidateSize() }, [map])
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
  filtered: Property[]
  filters: Filters
  sort: string
  setF: <K extends keyof Filters>(k: K, v: Filters[K]) => void
  toggleType: (t: string) => void
  setFilters: (f: Filters) => void
  setSort: (s: string) => void
}

const INIT: Filters = { minPrice: '', maxPrice: '', maxBeds: 0, types: [] }
const TYPES = ['flat', 'terraced', 'semi_detached', 'detached', 'bungalow']

export default function LayoutSplit({ filtered, filters, sort, setF, toggleType, setFilters, setSort, properties }: Props) {
  const [hoveredId, setHoveredId] = useState<number | null>(null)
  const rowRefs = useRef<Record<number, HTMLAnchorElement | null>>({})

  const mapItems = filtered.filter(p => p.latitude != null && p.longitude != null).slice(0, 300)

  return (
    <div className="l2-shell">
      <div className="l2-left">
        {/* Filter strip */}
        <div className="l2-filterbar">
          <span className="sb-label" style={{ marginBottom: 0, flexShrink: 0 }}>Price</span>
          <input
            className="l1-price-input"
            style={{ width: 80 }}
            type="number"
            placeholder="Min £"
            value={filters.minPrice}
            onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)}
          />
          <span style={{ color: 'var(--t4)', fontSize: '0.82rem' }}>—</span>
          <input
            className="l1-price-input"
            style={{ width: 80 }}
            type="number"
            placeholder="Max £"
            value={filters.maxPrice}
            onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)}
          />
          <div className="l1-sep" />
          {[0, 1, 2, 3, 4, 5].map(n => (
            <button
              key={n}
              className={`pill ${filters.maxBeds === n ? 'pill-on' : ''}`}
              style={{ padding: '4px 9px', fontSize: '0.76rem' }}
              onClick={() => setF('maxBeds', n)}
            >{n === 0 ? 'Any' : String(n)}</button>
          ))}
          <div className="l1-sep" />
          {TYPES.map(t => (
            <button
              key={t}
              className={`pill ${filters.types.includes(t) ? 'pill-on' : ''}`}
              style={{ padding: '4px 9px', fontSize: '0.76rem' }}
              onClick={() => toggleType(t)}
            >{t === 'semi_detached' ? 'Semi' : fmtLabel(t)}</button>
          ))}
          <button
            className="reset-btn"
            style={{ width: 'auto', marginTop: 0, padding: '4px 12px', flexShrink: 0, fontSize: '0.75rem' }}
            onClick={() => setFilters(INIT)}
          >Reset</button>
        </div>

        {/* Count + sort */}
        <div className="l2-count" style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ flex: 1 }}>{filtered.length.toLocaleString()} of {properties.length.toLocaleString()} properties</span>
          <select
            style={{ background: 'none', border: 'none', fontSize: '0.75rem', color: 'var(--t3)', cursor: 'pointer', outline: 'none' }}
            value={sort}
            onChange={e => setSort(e.target.value)}
          >
            <option value="newest">Newest</option>
            <option value="price_asc">Price low-high</option>
            <option value="price_desc">Price high-low</option>
            <option value="beds_asc">Fewest beds</option>
            <option value="beds_desc">Most beds</option>
          </select>
        </div>

        {/* Property list */}
        <div className="l2-list">
          {filtered.slice(0, 200).map(p => (
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
              </div>
              {p.property_type && (
                <span className="l2-badge">{p.property_type === 'semi_detached' ? 'Semi' : fmtLabel(p.property_type)}</span>
              )}
            </a>
          ))}
          {filtered.length === 0 && (
            <div style={{ padding: '60px 20px', textAlign: 'center', color: 'var(--t3)', fontSize: '0.85rem' }}>
              No properties match your filters.
              <br />
              <button className="reset-btn" style={{ display: 'inline-block', width: 'auto', marginTop: 12, padding: '6px 16px' }} onClick={() => setFilters(INIT)}>
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
                <strong>{p.title || p.address}</strong><br />
                {fmtPrice(p.price)}<br />
                {p.bedrooms != null && `${p.bedrooms} bed`}
              </Popup>
            </Marker>
          ))}
        </MapContainer>
      </div>
    </div>
  )
}
