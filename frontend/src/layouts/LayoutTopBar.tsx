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
}
const TYPES = ['flat', 'terraced', 'semi_detached', 'detached', 'bungalow']

export default function LayoutTopBar({ filtered, filters, sort, setF, toggleType, setFilters, setSort, properties }: Props) {
  return (
    <div className="l1-shell">
      <div className="l1-filterbar">
        <span className="l1-label">Price</span>
        <div className="l1-price-wrap">
          <input
            className="l1-price-input"
            type="number"
            placeholder="Min £"
            value={filters.minPrice}
            onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)}
          />
          <span style={{ color: 'var(--t4)', fontSize: '0.85rem' }}>—</span>
          <input
            className="l1-price-input"
            type="number"
            placeholder="Max £"
            value={filters.maxPrice}
            onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)}
          />
        </div>

        <div className="l1-sep" />

        <span className="l1-label">Beds</span>
        <div className="l1-pill-row">
          {[0, 1, 2, 3, 4, 5].map(n => (
            <button
              key={n}
              className={`pill ${filters.maxBeds === n ? 'pill-on' : ''}`}
              onClick={() => setF('maxBeds', n)}
            >{n === 0 ? 'Any' : String(n)}</button>
          ))}
        </div>

        <div className="l1-sep" />

        <span className="l1-label">Type</span>
        <div className="l1-pill-row">
          {TYPES.map(t => (
            <button
              key={t}
              className={`pill ${filters.types.includes(t) ? 'pill-on' : ''}`}
              onClick={() => toggleType(t)}
            >{t === 'semi_detached' ? 'Semi' : fmtLabel(t)}</button>
          ))}
        </div>

        <div className="l1-sep" />

        <button className="reset-btn" style={{ width: 'auto', marginTop: 0, padding: '5px 14px', whiteSpace: 'nowrap' }} onClick={() => setFilters(INIT)}>
          Reset
        </button>

        <span className="l1-count" style={{ marginLeft: 8 }}>
          {filtered.length.toLocaleString()} of {properties.length.toLocaleString()}
        </span>

        <select className="l1-sort" value={sort} onChange={e => setSort(e.target.value)}>
          <option value="newest">Newest</option>
          <option value="price_asc">Price: low to high</option>
          <option value="price_desc">Price: high to low</option>
          <option value="beds_asc">Beds: fewest first</option>
          <option value="beds_desc">Beds: most first</option>
        </select>
      </div>

      <div className="l1-grid">
        {filtered.slice(0, 80).map(p => (
          <article className="card" key={p.id}>
            <a
              href={`https://www.rightmove.co.uk/properties/${p.rightmove_id}`}
              target="_blank" rel="noreferrer"
              className="card-link"
            >
              <div className="card-img">
                {p.photo_url
                  ? <img src={p.photo_url} alt="" loading="lazy" />
                  : <div className="img-placeholder" />
                }
                {p.property_type && <span className="type-badge">{fmtLabel(p.property_type)}</span>}
              </div>
              <div className="card-body">
                <div className="card-price">{fmtPrice(p.price)}</div>
                <div className="card-title">{p.title || p.address}</div>
                <div className="card-addr">{p.address}</div>
                <div className="card-stats">
                  {p.bedrooms  != null && <span>{p.bedrooms} bed</span>}
                  {p.bathrooms != null && <span>{p.bathrooms} bath</span>}
                </div>
              </div>
            </a>
          </article>
        ))}
        {filtered.length === 0 && (
          <div className="empty">
            <p>No properties match your filters.</p>
            <button className="reset-btn" onClick={() => setFilters(INIT)}>Clear filters</button>
          </div>
        )}
      </div>
    </div>
  )
}
