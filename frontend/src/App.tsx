import { useMemo, useState } from 'react'
import { Routes, Route, useNavigate, useParams } from 'react-router-dom'
import type { Property } from './types/property'
import {
  useProperties,
  type LocationSearchParams,
  type MapBounds,
  type TransportationType,
} from './hooks/useProperties'
import { useModelSearch, type ModelSearchStatus } from './hooks/useModelSearch'
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

function ModelSearchIndicator({
  status,
  prompt,
  resultCount,
  error,
  onClear,
}: {
  status: ModelSearchStatus
  prompt: string
  resultCount: number
  error: string | null
  onClear: () => void
}) {
  if (status === 'idle') return null

  return (
    <div className="ms-indicator">
      {status === 'pending' && (
        <>
          <span className="ms-spinner" />
          <span className="ms-label">Searching&hellip;</span>
        </>
      )}
      {status === 'complete' && (
        <>
          <span className="ms-count">{resultCount}</span>
          <span className="ms-label ms-label-dim">
            {resultCount === 1 ? 'result' : 'results'} for &ldquo;{prompt.length > 40 ? prompt.slice(0, 40) + '…' : prompt}&rdquo;
          </span>
        </>
      )}
      {status === 'failed' && (
        <span className="ms-label ms-label-error">{error ?? 'Search failed'}</span>
      )}
      <button type="button" className="ms-clear" onClick={onClear} title="Clear search">
        <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
          <path d="M1 1l8 8M9 1L1 9" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round"/>
        </svg>
      </button>
    </div>
  )
}

interface AppHeaderProps {
  locationSearch: LocationSearchParams
  onLocationQueryChange: (value: string) => void
  onApplyLocationSearch: (queryOverride?: string) => boolean
  onModelSearch: (prompt: string) => void
  onClearModelSearch: () => void
  modelSearchStatus: ModelSearchStatus
  modelSearchPrompt: string
  modelSearchResultCount: number
  modelSearchError: string | null
}

function AppHeader({
  locationSearch,
  onLocationQueryChange,
  onApplyLocationSearch,
  onModelSearch,
  onClearModelSearch,
  modelSearchStatus,
  modelSearchPrompt,
  modelSearchResultCount,
  modelSearchError,
}: AppHeaderProps) {
  const navigate = useNavigate()

  return (
    <header className="header">
      <div className="header-brand" style={{ cursor: 'pointer' }} onClick={() => navigate('/')}>
        <FlameIcon size={22} />
        <span className="brand-name">Hestia</span>
        <span className="brand-tagline">find your home</span>
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
            const query = locationSearch.query.trim()
            if (!query) return
            onModelSearch(query)
            navigate('/')
          }}
          onSelect={suggestion => {
            onClearModelSearch()
            if (onApplyLocationSearch(suggestion.label)) navigate('/')
          }}
          inputClassName="header-search"
          placeholder="Describe your ideal home, or pick a location below"
          theme="dark"
        />
      </div>
      <ModelSearchIndicator
        status={modelSearchStatus}
        prompt={modelSearchPrompt}
        resultCount={modelSearchResultCount}
        error={modelSearchError}
        onClear={onClearModelSearch}
      />
    </header>
  )
}

// ─── Filter state ────────────────────────────────────────────────────────────
export interface Filters {
  minPrice:           number | ''
  maxPrice:           number | ''
  minBeds:            number
  maxBeds:            number
  types:              string[]
  maxStationMinutes:  number
  maxCrimeRate:       number | ''
  minPricePerSqft:    number | ''
  maxPricePerSqft:    number | ''
  maxDaqi:            number
  minFloodRisk:       number
  maxFloodRisk:       number
  maxRoadNoiseLden:   number | ''
  maxRailNoiseLden:   number | ''
  maxFlightNoiseLden: number | ''
  minAgentRating:     number | ''
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxStationMinutes: 0, maxCrimeRate: '', minPricePerSqft: '', maxPricePerSqft: '', maxDaqi: 0, minFloodRisk: 0, maxFloodRisk: 0, maxRoadNoiseLden: '', maxRailNoiseLden: '', maxFlightNoiseLden: '', minAgentRating: '' }
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
  modelSearchActive: boolean
  modelSearchProperties: Property[]
  modelSearchLoading: boolean
  modelSearchError: string | null
}

// ─── Search page ─────────────────────────────────────────────────────────────
function SearchPage({
  locationSearchDraft,
  appliedLocationSearch,
  onLocationSearchFieldChange,
  onApplyLocationSearch,
  onClearLocationSearch,
  modelSearchActive,
  modelSearchProperties,
  modelSearchLoading,
  modelSearchError,
}: SearchPageProps) {
  const navigate = useNavigate()
  const [mapBounds, setMapBounds] = useState<MapBounds | null>(null)
  const [filters, setFilters] = useState<Filters>(INIT)
  const [sort, setSort]       = useState<SortKey>('newest')

  const { properties: locationProperties, total: locationTotal, loading: locationLoading, error: locationError, activeLocationSearch } =
    useProperties(modelSearchActive ? null : mapBounds, modelSearchActive ? null : appliedLocationSearch)

  const locationSearchError = appliedLocationSearch && !modelSearchActive ? locationError : null
  const viewportError       = appliedLocationSearch || modelSearchActive ? null : locationError
  const locationSearchLoading = locationLoading && appliedLocationSearch !== null && !modelSearchActive

  // When model search is active, use its results instead of the location/viewport results
  const properties = modelSearchActive ? modelSearchProperties : locationProperties
  const total      = modelSearchActive ? modelSearchProperties.length : locationTotal
  const loading    = modelSearchActive ? modelSearchLoading : locationLoading

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
      if (filters.maxDaqi > 0) {
        const idx = p.air_quality?.daqi_index
        if (idx == null || idx > filters.maxDaqi) return false
      }
      if (filters.minFloodRisk > 0) {
        const band = p.flood_risk?.risk_band
        if (band == null || band < filters.minFloodRisk) return false
      }
      if (filters.maxFloodRisk > 0) {
        const band = p.flood_risk?.risk_band
        if (band == null || band > filters.maxFloodRisk) return false
      }
      if (filters.maxRoadNoiseLden !== '') {
        const lden = p.noise?.road_data?.metrics?.lden
        if (lden != null && lden > (filters.maxRoadNoiseLden as number)) return false
      }
      if (filters.maxRailNoiseLden !== '') {
        const lden = p.noise?.rail_data?.metrics?.lden
        if (lden != null && lden > (filters.maxRailNoiseLden as number)) return false
      }
      if (filters.maxFlightNoiseLden !== '') {
        const lden = p.noise?.flight_data?.metrics?.lden
        if (lden != null && lden > (filters.maxFlightNoiseLden as number)) return false
      }
      if (filters.minAgentRating !== '') {
        const rating = p.estate_agent?.rating
        if (rating == null || rating < (filters.minAgentRating as number)) return false
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
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
      {modelSearchError && (
        <div className="ms-error-banner">{modelSearchError}</div>
      )}
      <div className="shell" style={{ overflow: 'hidden', flex: 1 }}>
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
        activeLocationSearch={activeLocationSearch}
      />
      </div>
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

  const modelSearch = useModelSearch()

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

  const modelSearchActive = modelSearch.status !== 'idle'

  return (
    <div className="app">
      <AppHeader
        locationSearch={locationSearchDraft}
        onLocationQueryChange={value => setLocationSearchField('query', value)}
        onApplyLocationSearch={applyLocationSearch}
        onModelSearch={prompt => {
          clearLocationSearch()
          modelSearch.trigger(prompt)
        }}
        onClearModelSearch={() => {
          modelSearch.clear()
          setLocationSearchDraft(current => ({ ...current, query: '' }))
        }}
        modelSearchStatus={modelSearch.status}
        modelSearchPrompt={modelSearch.prompt}
        modelSearchResultCount={modelSearch.properties.length}
        modelSearchError={modelSearch.error}
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
              modelSearchActive={modelSearchActive}
              modelSearchProperties={modelSearch.properties}
              modelSearchLoading={modelSearch.status === 'pending'}
              modelSearchError={modelSearch.error}
            />
          }
        />
        <Route path="/properties/:id" element={<PropertyDetailPage />} />
      </Routes>
    </div>
  )
}
