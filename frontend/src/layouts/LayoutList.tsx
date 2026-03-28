import type { Property } from '../types/property'
import type { Filters } from '../App'
import './layouts.css'
import '../App.css'

function fmtPrice(pence: number) {
  return '£' + Math.round(pence / 100).toLocaleString('en-GB')
}
function fmtLabel(s: string) {
  return s.replace(/_/g, '-').replace(/\b\w/g, c => c.toUpperCase())
}

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

const INIT: Filters = {
  minPrice: '',
  maxPrice: '',
  minBeds: 0,
  maxBeds: 0,
  types: [],
  maxStationMinutes: 0,
  maxCrimeRate: '',
  minPricePerSqft: '',
  maxPricePerSqft: '',
  maxDaqi: 0,
}
const TYPES = ['flat', 'terraced', 'semi_detached', 'detached', 'bungalow']

export default function LayoutList({ filtered, filters, sort, setF, toggleType, setFilters, setSort, properties }: Props) {
  return (
    <div className="l4-shell">
      {/* Sidebar — same as current app */}
      <aside className="l4-sidebar">
        <div className="sb-inner">
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
            <h4 className="sb-label">Max Bedrooms</h4>
            <div className="pill-row">
              {[0, 1, 2, 3, 4, 5].map(n => (
                <button
                  key={n}
                  className={`pill ${filters.maxBeds === n ? 'pill-on' : ''}`}
                  onClick={() => setF('maxBeds', n)}
                >{n === 0 ? 'Any' : String(n)}</button>
              ))}
            </div>
          </section>

          <section className="sb-section">
            <h4 className="sb-label">Property Type</h4>
            <div className="check-grid">
              {TYPES.map(t => (
                <label key={t} className={`check-pill ${filters.types.includes(t) ? 'check-on' : ''}`}>
                  <input type="checkbox" checked={filters.types.includes(t)} onChange={() => toggleType(t)} />
                  {t === 'semi_detached' ? 'Semi' : fmtLabel(t)}
                </label>
              ))}
            </div>
          </section>

          <button className="reset-btn" onClick={() => setFilters(INIT)}>
            Reset all filters
          </button>
        </div>
      </aside>

      {/* Content */}
      <div className="l4-content">
        <div className="l4-toolbar">
          <span className="l4-count">
            <strong>{filtered.length.toLocaleString()}</strong> of {properties.length.toLocaleString()} properties
          </span>
          <select className="l4-sort" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="newest">Newest</option>
            <option value="price_asc">Price: low to high</option>
            <option value="price_desc">Price: high to low</option>
            <option value="beds_asc">Beds: fewest first</option>
            <option value="beds_desc">Beds: most first</option>
          </select>
        </div>

        <div className="l4-list">
          {filtered.slice(0, 200).map(p => (
            <a
              key={p.id}
              className="l4-row"
              href={`https://www.rightmove.co.uk/properties/${p.rightmove_id}`}
              target="_blank"
              rel="noreferrer"
            >
              <div className="l4-thumb">
                {p.photo_url
                  ? <img src={p.photo_url} alt="" loading="lazy" />
                  : <div className="l4-thumb-ph" />
                }
              </div>
              <div className="l4-price">{fmtPrice(p.price)}</div>
              <div className="l4-mid">
                <div className="l4-title">{p.title || p.address}</div>
                <div className="l4-addr">{p.address}</div>
                <div className="l4-stats">
                  {p.bedrooms  != null && <span>{p.bedrooms} bed</span>}
                  {p.bathrooms != null && <span>{p.bathrooms} bath</span>}
                </div>
              </div>
              {p.property_type && (
                <span className="l4-badge">{p.property_type === 'semi_detached' ? 'Semi' : fmtLabel(p.property_type)}</span>
              )}
            </a>
          ))}
          {filtered.length === 0 && (
            <div style={{ padding: '80px 40px', textAlign: 'center', color: 'var(--t3)', fontStyle: 'italic' }}>
              No properties match your filters.
              <br />
              <button className="reset-btn" style={{ display: 'inline-block', width: 'auto', marginTop: 14, padding: '6px 18px' }} onClick={() => setFilters(INIT)}>
                Clear filters
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
