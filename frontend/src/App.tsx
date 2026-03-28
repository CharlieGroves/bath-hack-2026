import { useMemo, useState } from 'react'
import { Routes, Route, useNavigate, useParams } from 'react-router-dom'
import type { Property } from './types/property'
import {
  useProperties,
  type LocationSearchParams,
  type MapBounds,
  type TransportationType,
} from './hooks/useProperties'
import LayoutSplit from './layouts/LayoutSplit'
import LocationAutocompleteInput from './components/LocationAutocompleteInput'
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

interface AppHeaderProps {
  locationSearch: LocationSearchParams
  onLocationQueryChange: (value: string) => void
  onApplyLocationSearch: (queryOverride?: string) => boolean
}

function AppHeader({ locationSearch, onLocationQueryChange, onApplyLocationSearch }: AppHeaderProps) {
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
        <LocationAutocompleteInput
          value={locationSearch.query}
          onChange={onLocationQueryChange}
          onEnter={() => {
            if (onApplyLocationSearch()) navigate('/')
          }}
          onSelect={suggestion => {
            if (onApplyLocationSearch(suggestion.label)) navigate('/')
          }}
          inputClassName="header-search"
          placeholder="Where would you like to live?"
          theme="dark"
        />
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
  minPricePerSqft:   number | ''
  maxPricePerSqft:   number | ''
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '', minPricePerSqft: '', maxPricePerSqft: '' }
const DEFAULT_LOCATION_SEARCH: LocationSearchParams = {
  query: '',
  transportationType: 'driving',
  travelTimeMinutes: 15,
}

type SortKey = 'price_asc' | 'price_desc' | 'beds_asc' | 'beds_desc' | 'newest'

interface SearchPageProps {
  locationSearchDraft: LocationSearchParams
  appliedLocationSearch: LocationSearchParams | null
  onLocationSearchFieldChange: <K extends keyof LocationSearchParams>(key: K, value: LocationSearchParams[K]) => void
  onApplyLocationSearch: (queryOverride?: string) => boolean
  onClearLocationSearch: () => void
}

// ─── Search page ─────────────────────────────────────────────────────────────
function SearchPage({
  locationSearchDraft,
  appliedLocationSearch,
  onLocationSearchFieldChange,
  onApplyLocationSearch,
  onClearLocationSearch,
}: SearchPageProps) {
  const navigate = useNavigate()
  const [mapBounds, setMapBounds] = useState<MapBounds | null>(null)
  const [filters, setFilters] = useState<Filters>(INIT)
  const [sort, setSort]       = useState<SortKey>('newest')
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
      if (filters.minPricePerSqft !== '') {
        if (p.price_per_sqft == null || p.price_per_sqft < (filters.minPricePerSqft as number) * 100) return false
      }
      if (filters.maxPricePerSqft !== '') {
        if (p.price_per_sqft == null || p.price_per_sqft > (filters.maxPricePerSqft as number) * 100) return false
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
        onLocationQueryChange={value => onLocationSearchFieldChange('query', value)}
        onTransportationTypeChange={value => onLocationSearchFieldChange('transportationType', value as TransportationType)}
        onTravelTimeMinutesChange={value => onLocationSearchFieldChange('travelTimeMinutes', value)}
        onApplyLocationSearch={onApplyLocationSearch}
        onClearLocationSearch={onClearLocationSearch}
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
  const [locationSearchDraft, setLocationSearchDraft] = useState<LocationSearchParams>(DEFAULT_LOCATION_SEARCH)
  const [appliedLocationSearch, setAppliedLocationSearch] = useState<LocationSearchParams | null>(null)

  function setLocationSearchField<K extends keyof LocationSearchParams>(key: K, value: LocationSearchParams[K]) {
    setLocationSearchDraft(current => ({ ...current, [key]: value }))
  }

  function applyLocationSearch(queryOverride?: string) {
    const query = (queryOverride ?? locationSearchDraft.query).trim()
    if (!query) {
      setAppliedLocationSearch(null)
      return false
    }

    setLocationSearchDraft(current => ({ ...current, query }))
    setAppliedLocationSearch({
      ...locationSearchDraft,
      query,
    })
    return true
  }

  function clearLocationSearch() {
    setAppliedLocationSearch(null)
    setLocationSearchDraft(current => ({ ...current, query: '' }))
  }

  return (
    <div className="app">
      <AppHeader
        locationSearch={locationSearchDraft}
        onLocationQueryChange={value => setLocationSearchField('query', value)}
        onApplyLocationSearch={applyLocationSearch}
      />
      <Routes>
        <Route
          path="/"
          element={
            <SearchPage
              locationSearchDraft={locationSearchDraft}
              appliedLocationSearch={appliedLocationSearch}
              onLocationSearchFieldChange={setLocationSearchField}
              onApplyLocationSearch={applyLocationSearch}
              onClearLocationSearch={clearLocationSearch}
            />
          }
        />
        <Route path="/properties/:id" element={<PropertyDetailPage />} />
      </Routes>
    </div>
  )
}
