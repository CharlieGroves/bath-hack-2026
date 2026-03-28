import { useState, useMemo } from 'react'
import type { Property } from './types/property'
import { useProperties } from './hooks/useProperties'
import LayoutSplit from './layouts/LayoutSplit'
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

// ─── Filter state ────────────────────────────────────────────────────────────
export interface Filters {
  minPrice:     number | ''
  maxPrice:     number | ''
  minBeds:      number
  maxBeds:      number
  types:        string[]
  maxCrimeRate: number | ''
}

const INIT: Filters = { minPrice: '', maxPrice: '', minBeds: 0, maxBeds: 0, types: [], maxCrimeRate: '' }

type SortKey = 'price_asc' | 'price_desc' | 'beds_asc' | 'beds_desc' | 'newest'

// ─── Main App ────────────────────────────────────────────────────────────────
export default function App() {
  const { properties, loading, error } = useProperties()

  const [filters, setFilters] = useState<Filters>(INIT)
  const [sort, setSort]       = useState<SortKey>('newest')

  const filtered = useMemo(() => {
    const result = properties.filter((p: Property) => {
      if (filters.minPrice !== '' && p.price < (filters.minPrice as number) * 100) return false
      if (filters.maxPrice !== '' && p.price > (filters.maxPrice as number) * 100) return false
      if (filters.minBeds > 0 && (p.bedrooms ?? 0) < filters.minBeds) return false
      if (filters.maxBeds > 0 && (p.bedrooms ?? 0) > filters.maxBeds) return false
      if (filters.types.length && !filters.types.includes(p.property_type)) return false
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

  if (loading) return (
    <div className="splash">
      <FlameIcon size={40} />
      <p className="splash-text">Finding your perfect home...</p>
    </div>
  )
  if (error) return <div className="splash"><p>Error: {error}</p></div>

  return (
    <div className="app">
      <header className="header">
        <div className="header-brand">
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

      <div className="shell" style={{ overflow: 'hidden' }}>
        <LayoutSplit
          properties={properties}
          filtered={filtered}
          filters={filters}
          sort={sort}
          setF={setF}
          toggleType={toggleType}
          setFilters={setFilters}
          setSort={s => setSort(s as SortKey)}

        />
      </div>
    </div>
  )
}
