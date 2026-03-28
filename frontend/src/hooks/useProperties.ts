import { useEffect, useState, useRef } from 'react'
import type { BoundingBox, Property, SearchLocation } from '../types/property'

export interface MapBounds {
  sw_lat: number
  sw_lng: number
  ne_lat: number
  ne_lng: number
}

export type TransportationType = 'driving' | 'walking' | 'cycling' | 'public_transport'

export interface LocationSearchParams {
  query: string
  transportationType: TransportationType
  travelTimeMinutes: number
}

export interface ActiveLocationSearch {
  query: string
  location: SearchLocation
  transportationType: TransportationType
  travelTimeMinutes: number
  boundingBox: BoundingBox
}

interface UsePropertiesResult {
  properties: Property[]
  total: number
  loading: boolean
  error: string | null
  activeLocationSearch: ActiveLocationSearch | null
}

// Debounce delay in ms — avoids hammering the API while the map is mid-drag
const DEBOUNCE_MS = 300

export function useProperties(
  bounds: MapBounds | null,
  locationSearchParams: LocationSearchParams | null,
): UsePropertiesResult {
  const [properties, setProperties] = useState<Property[]>([])
  const [total, setTotal]           = useState(0)
  const [loading, setLoading]       = useState(false)
  const [error, setError]           = useState<string | null>(null)
  const [activeLocationSearch, setActiveLocationSearch] = useState<ActiveLocationSearch | null>(null)

  const abortRef      = useRef<AbortController | null>(null)
  const timerRef      = useRef<ReturnType<typeof setTimeout> | null>(null)
  const hasLoadedOnce = useRef(false)
  const swLat = bounds?.sw_lat
  const swLng = bounds?.sw_lng
  const neLat = bounds?.ne_lat
  const neLng = bounds?.ne_lng
  const searchQuery = locationSearchParams?.query ?? ''
  const transportationType = locationSearchParams?.transportationType
  const travelTimeMinutes = locationSearchParams?.travelTimeMinutes

  useEffect(() => {
    const trimmedQuery = searchQuery.trim()
    const hasLocationSearch = trimmedQuery.length > 0
    if (!hasLocationSearch && (swLat == null || swLng == null || neLat == null || neLng == null)) return

    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      abortRef.current?.abort()
      abortRef.current = new AbortController()

      const params = hasLocationSearch
        ? new URLSearchParams({
            query: trimmedQuery,
            transportation_type: transportationType!,
            travel_time_minutes: String(travelTimeMinutes!),
          })
        : new URLSearchParams({
            sw_lat: String(swLat),
            sw_lng: String(swLng),
            ne_lat: String(neLat),
            ne_lng: String(neLng),
          })

      const endpoint = hasLocationSearch ? '/api/v1/properties/search' : '/api/v1/properties'

      if (!hasLoadedOnce.current || hasLocationSearch) setLoading(true)
      fetch(`${endpoint}?${params}`, { signal: abortRef.current.signal })
        .then(async res => {
          const payload = await res.json().catch(() => null)
          if (!res.ok) {
            const message = typeof payload?.error === 'string' ? payload.error : `HTTP ${res.status}`
            throw new Error(message)
          }
          return payload
        })
        .then(data => {
          setProperties(data.properties)
          setTotal(data.total)
          setError(null)
          if (hasLocationSearch) {
            setActiveLocationSearch({
              query: data.query,
              location: data.location,
              transportationType: data.transportation_type,
              travelTimeMinutes: Math.round(data.travel_time_seconds / 60),
              boundingBox: data.bounding_box,
            })
          } else {
            setActiveLocationSearch(null)
          }
          hasLoadedOnce.current = true
        })
        .catch(err => {
          if (err.name !== 'AbortError') setError(err.message)
        })
        .finally(() => setLoading(false))
    }, hasLocationSearch ? 0 : DEBOUNCE_MS)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [
    swLat,
    swLng,
    neLat,
    neLng,
    searchQuery,
    transportationType,
    travelTimeMinutes,
  ])

  return { properties, total, loading, error, activeLocationSearch }
}
