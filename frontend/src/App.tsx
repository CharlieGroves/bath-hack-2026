import { useState, useMemo } from 'react'
import { Routes, Route, useNavigate, useParams } from 'react-router-dom'
import type { Property } from './types/property'
import {
  useProperties,
  type LocationSearchParams,
  type MapBounds,
  type TransportationType,
} from './hooks/useProperties'
import LayoutSplit from './layouts/LayoutSplit'
import PropertyPage from './components/PropertyPage'
import './App.css'

// ─── Helpers ────────────────────────────────────────────────────────────────
function FlameIcon({ size = 24 }: { size?: number }) {
  return (
    <svg width={size} height={size * 1.2} viewBox="0 0 20 24" fill="none">
      <path d="M10 1C10 1 3 9 3 15.5a7 7 0 0014 0C17 9.5 10 1 10 1z" fill="#E76814"/>
      <path d="M10 9C10 9 7 13.5 7 16.5a3 3 0 006 0C13 13.5 10 9 10 9z" fill="#F25016"/>
      <ellipse cx="10" cy="19" rx="2" ry="1.4" fill="#DC8236"/>
    </svg>
  )
}

function AppHeader() {
  const navigate = useNavigate()
  return (
    <header className="header">
      <div className="header-brand" style={{ cursor: 'pointer' }} onClick={() => navigate('/')}>
        <FlameIcon size={22} />
        <span className="brand-name">Hearthstone</span>
      </div>
      <div className="header-search-wrap">
        <svg className="search-icon" width="15" height="15" viewBox="0 0 15 15" fill="none">
          <circle cx="6.5" cy="6.5" r="5" stroke="currentColor" strokeWidth="1.5"/>
          <path d="M10.5 10.5L14 14" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
        </svg>
        <input className="header-search" type="text" placeholder="Where would you like to live?" />
      </div>
    </header>
  )
}

// ─── Filter state ────────────────────────────────────────────────────────────
export interface Filters {
  minPrice:          number | ''
  maxPrice:          number | ''
  minBeds:           number
  maxBeds:           number
  types:             string[]
  maxStationMinutes: number
  maxCrimeRate:      number | ''
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '' }
const DEFAULT_LOCATION_SEARCH: LocationSearchParams = {
  query: '',
  transportationType: 'driving',
  travelTimeMinutes: 15,
}

type SortKey = 'price_asc' | 'price_desc' | 'beds_asc' | 'beds_desc' | 'newest'

// ─── Search page ─────────────────────────────────────────────────────────────
function SearchPage() {
  const navigate = useNavigate()
  const [mapBounds, setMapBounds] = useState<MapBounds | null>(null)
  const [filters, setFilters] = useState<Filters>(INIT)
  const [sort, setSort]       = useState<SortKey>('newest')
  const [locationSearchDraft, setLocationSearchDraft] = useState<LocationSearchParams>(DEFAULT_LOCATION_SEARCH)
  const [appliedLocationSearch, setAppliedLocationSearch] = useState<LocationSearchParams | null>(null)
  const { properties, total, loading, error, activeLocationSearch } = useProperties(mapBounds, appliedLocationSearch)
  const locationSearchError = appliedLocationSearch ? error : null
  const viewportError = appliedLocationSearch ? null : error
  const locationSearchLoading = loading && appliedLocationSearch !== null

  const filtered = useMemo(() => {
    const result = properties.filter((p: Property) => {
      if (filters.minPrice !== '' && p.price < (filters.minPrice as number) * 100) return false
      if (filters.maxPrice !== '' && p.price > (filters.maxPrice as number) * 100) return false
      if (filters.minBeds > 0 && (p.bedrooms ?? 0) < filters.minBeds) return false
      if (filters.maxBeds > 0 && (p.bedrooms ?? 0) > filters.maxBeds) return false
      if (filters.types.length && !filters.types.includes(p.property_type)) return false
      if (filters.maxStationMinutes > 0) {
        const closest = Math.min(...(p.nearest_stations ?? []).map(s => s.walking_minutes))
        if (!isFinite(closest) || closest > filters.maxStationMinutes) return false
      }
      if (filters.maxCrimeRate !== '') {
        const avg = p.crime?.avg_monthly_crimes
        if (avg == null || avg > (filters.maxCrimeRate as number)) return false
      }
      return true
    })
    return [...result].sort((a: Property, b: Property) => {
      switch (sort) {
        case 'price_asc':  return a.price - b.price
        case 'price_desc': return b.price - a.price
        case 'beds_asc':   return (a.bedrooms ?? 0) - (b.bedrooms ?? 0)
        case 'beds_desc':  return (b.bedrooms ?? 0) - (a.bedrooms ?? 0)
        case 'newest':     return new Date(b.listed_at).getTime() - new Date(a.listed_at).getTime()
      }
    })
  }, [properties, filters, sort])

  function setF<K extends keyof Filters>(k: K, v: Filters[K]) {
    setFilters(f => ({ ...f, [k]: v }))
  }
  function toggleType(t: string) {
    setFilters(f => ({
      ...f,
      types: f.types.includes(t) ? f.types.filter(x => x !== t) : [...f.types, t],
    }))
  }
  function setLocationSearchField<K extends keyof LocationSearchParams>(key: K, value: LocationSearchParams[K]) {
    setLocationSearchDraft(current => ({ ...current, [key]: value }))
  }
  function applyLocationSearch() {
    const query = locationSearchDraft.query.trim()
    if (!query) {
      setAppliedLocationSearch(null)
      return
    }

    setAppliedLocationSearch({
      ...locationSearchDraft,
      query,
    })
  }
  function clearLocationSearch() {
    setAppliedLocationSearch(null)
    setLocationSearchDraft(current => ({ ...current, query: '' }))
  }

  return (
    <div className="shell" style={{ overflow: 'hidden' }}>
      <LayoutSplit
        properties={properties}
        total={total}
        loading={loading}
        filtered={filtered}
        filters={filters}
        sort={sort}
        setF={setF}
        toggleType={toggleType}
        setFilters={setFilters}
        setSort={s => setSort(s as SortKey)}
        onBoundsChange={setMapBounds}
        onSelectProperty={id => navigate(`/properties/${id}`)}
        viewportError={viewportError}
        locationSearchError={locationSearchError}
        locationSearchLoading={locationSearchLoading}
        locationSearch={locationSearchDraft}
        activeLocationSearch={activeLocationSearch}
        onLocationQueryChange={value => setLocationSearchField('query', value)}
        onTransportationTypeChange={value => setLocationSearchField('transportationType', value as TransportationType)}
        onTravelTimeMinutesChange={value => setLocationSearchField('travelTimeMinutes', value)}
        onApplyLocationSearch={applyLocationSearch}
        onClearLocationSearch={clearLocationSearch}
      />
    </div>
  )
}

// ─── Property detail page ─────────────────────────────────────────────────────
function PropertyDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  return (
    <PropertyPage
      propertyId={Number(id)}
      onBack={() => navigate('/')}
    />
  )
}

// ─── Main App ────────────────────────────────────────────────────────────────
export default function App() {
  return (
    <div className="app">
      <AppHeader />
      <Routes>
        <Route path="/" element={<SearchPage />} />
        <Route path="/properties/:id" element={<PropertyDetailPage />} />
      </Routes>
    </div>
  )
}
