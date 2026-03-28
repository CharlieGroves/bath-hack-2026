import { useEffect, useState } from 'react'
import type { Property, PropertyLocationSearchResult } from '../types/property'

interface PropertiesResponse {
  properties: Property[]
  total: number
}

interface SearchByLocationParams {
  query: string
  transportationType: string
  travelTimeMinutes: number
}

interface UsePropertiesResult {
  properties: Property[]
  total: number
  loading: boolean
  searching: boolean
  error: string | null
  searchResult: PropertyLocationSearchResult | null
  searchByLocation: (params: SearchByLocationParams) => Promise<void>
  resetSearch: () => void
}

export function useProperties(): UsePropertiesResult {
  const [allProperties, setAllProperties] = useState<Property[]>([])
  const [allTotal, setAllTotal] = useState(0)
  const [properties, setProperties] = useState<Property[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [searching, setSearching] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [searchResult, setSearchResult] = useState<PropertyLocationSearchResult | null>(null)

  useEffect(() => {
    void loadAllProperties()
  }, [])

  async function loadAllProperties() {
    setLoading(true)
    setError(null)

    try {
      const data = await fetchJson<PropertiesResponse>('/api/v1/properties')
      setAllProperties(data.properties)
      setAllTotal(data.total)
      setProperties(data.properties)
      setTotal(data.total)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load properties')
    } finally {
      setLoading(false)
    }
  }

  async function searchByLocation({
    query,
    transportationType,
    travelTimeMinutes,
  }: SearchByLocationParams) {
    setSearching(true)
    setError(null)

    const params = new URLSearchParams({
      query,
      transportation_type: transportationType,
      travel_time_minutes: String(travelTimeMinutes),
    })

    try {
      const data = await fetchJson<PropertyLocationSearchResult>(`/api/v1/properties/search?${params.toString()}`)
      setSearchResult(data)
      setProperties(data.properties)
      setTotal(data.total)
    } catch (err) {
      setSearchResult(null)
      setProperties(allProperties)
      setTotal(allTotal)
      setError(err instanceof Error ? err.message : 'Location search failed')
    } finally {
      setSearching(false)
    }
  }

  function resetSearch() {
    setSearchResult(null)
    setProperties(allProperties)
    setTotal(allTotal)
    setError(null)
  }

  return { properties, total, loading, searching, error, searchResult, searchByLocation, resetSearch }
}

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url)
  const payload = await response.json().catch(() => null)

  if (!response.ok) {
    const message =
      payload && typeof payload === 'object' && 'error' in payload && typeof payload.error === 'string'
        ? payload.error
        : `HTTP ${response.status}`

    throw new Error(message)
  }

  return payload as T
}
