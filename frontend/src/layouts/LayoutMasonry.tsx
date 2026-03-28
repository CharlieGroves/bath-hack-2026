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
}
const TYPES = ['flat', 'terraced', 'semi_detached', 'detached', 'bungalow']

export default function LayoutMasonry({ filtered, filters, sort, setF, toggleType, setFilters, setSort, properties }: Props) {
  const [hero, ...rest] = filtered

  return (
    <div className="l3-shell">
      {/* Slim sidebar */}
      <aside className="l3-sidebar">
        <span className="l3-sid-label">Sort</span>
        <select className="l3-sort" value={sort} onChange={e => setSort(e.target.value)}>
          <option value="newest">Newest</option>
          <option value="price_asc">Price: low to high</option>
          <option value="price_desc">Price: high to low</option>
          <option value="beds_asc">Beds: fewest first</option>
          <option value="beds_desc">Beds: most first</option>
        </select>

        <span className="l3-sid-label" style={{ marginTop: 20 }}>Price range</span>
        <div className="l3-price-wrap">
          <input
            className="l3-price-input"
            type="number"
            placeholder="Min £"
            value={filters.minPrice}
            onChange={e => setF('minPrice', e.target.value === '' ? '' : +e.target.value)}
          />
          <input
            className="l3-price-input"
            type="number"
            placeholder="Max £"
            value={filters.maxPrice}
            onChange={e => setF('maxPrice', e.target.value === '' ? '' : +e.target.value)}
          />
        </div>

        <span className="l3-sid-label" style={{ marginTop: 20 }}>Max beds</span>
        <div className="l3-pill-col">
          {[0, 1, 2, 3, 4, 5].map(n => (
            <button
              key={n}
              className={`pill ${filters.maxBeds === n ? 'pill-on' : ''}`}
              style={{ textAlign: 'left' }}
              onClick={() => setF('maxBeds', n)}
            >{n === 0 ? 'Any' : `Up to ${n}`}</button>
          ))}
        </div>

        <span className="l3-sid-label" style={{ marginTop: 20 }}>Type</span>
        <div className="l3-type-row">
          {TYPES.map(t => (
            <label key={t} className="l3-check">
              <input
                type="checkbox"
                checked={filters.types.includes(t)}
                onChange={() => toggleType(t)}
              />
              {t === 'semi_detached' ? 'Semi-detached' : fmtLabel(t)}
            </label>
          ))}
        </div>

        <button
          className="reset-btn"
          style={{ marginTop: 22 }}
          onClick={() => setFilters(INIT)}
        >
          Reset filters
        </button>

        <p style={{ marginTop: 14, fontSize: '0.72rem', color: 'var(--t4)' }}>
          {filtered.length.toLocaleString()} of {properties.length.toLocaleString()} properties
        </p>
      </aside>

      {/* Content */}
      <div className="l3-content">
        {filtered.length === 0 ? (
          <div className="empty">
            <p>No properties match your filters.</p>
            <button className="reset-btn" style={{ width: 'auto', padding: '7px 20px' }} onClick={() => setFilters(INIT)}>Clear filters</button>
          </div>
        ) : (
          <>
            {/* Hero card */}
            {hero && (
              <a
                className="l3-hero"
                href={`https://www.rightmove.co.uk/properties/${hero.rightmove_id}`}
                target="_blank"
                rel="noreferrer"
              >
                <div className="l3-hero-img">
                  {hero.photo_url
                    ? <img src={hero.photo_url} alt="" loading="lazy" />
                    : <div style={{ width: '100%', height: '100%', background: 'var(--sb-bg)' }} />
                  }
                </div>
                <div className="l3-hero-body">
                  {hero.property_type && (
                    <div className="l3-hero-type">{fmtLabel(hero.property_type)}</div>
                  )}
                  <div className="l3-hero-price">{fmtPrice(hero.price)}</div>
                  <div className="l3-hero-title">{hero.title || hero.address}</div>
                  <div className="l3-hero-addr">{hero.address}</div>
                  <div className="l3-hero-stats">
                    {hero.bedrooms  != null && <span>{hero.bedrooms} bedrooms</span>}
                    {hero.bathrooms != null && <span>{hero.bathrooms} bathrooms</span>}
                  </div>
                </div>
              </a>
            )}

            {/* Masonry grid */}
            <div className="l3-masonry">
              {rest.slice(0, 59).map(p => (
                <a
                  key={p.id}
                  className="l3-card"
                  href={`https://www.rightmove.co.uk/properties/${p.rightmove_id}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  <div className="l3-card-img">
                    {p.photo_url
                      ? <img src={p.photo_url} alt="" loading="lazy" />
                      : <div style={{ height: '100%', background: 'var(--sb-bg)' }} />
                    }
                    {p.property_type && <span className="l3-card-badge">{fmtLabel(p.property_type)}</span>}
                  </div>
                  <div className="l3-card-body">
                    <div className="l3-card-price">{fmtPrice(p.price)}</div>
                    <div className="l3-card-title">{p.title || p.address}</div>
                    <div className="l3-card-addr">{p.address}</div>
                    <div className="l3-card-stats">
                      {p.bedrooms  != null && <span>{p.bedrooms} bed</span>}
                      {p.bathrooms != null && <span>{p.bathrooms} bath</span>}
                    </div>
                  </div>
                </a>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
