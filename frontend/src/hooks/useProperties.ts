import { useEffect, useState, useRef } from 'react'
import type { BoundingBox, IsochronePoint, Property, SearchLocation } from '../types/property'

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
  isochroneShells: IsochronePoint[][]
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
    if (trimmedQuery.length > 0) return
    if (swLat == null || swLng == null || neLat == null || neLng == null) return

    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      abortRef.current?.abort()
      abortRef.current = new AbortController()

      const params = new URLSearchParams({
        sw_lat: String(swLat),
        sw_lng: String(swLng),
        ne_lat: String(neLat),
        ne_lng: String(neLng),
      })

      if (!hasLoadedOnce.current) setLoading(true)
      fetch(`/api/v1/properties?${params}`, { signal: abortRef.current.signal })
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
          setActiveLocationSearch(null)
          hasLoadedOnce.current = true
        })
        .catch(err => {
          if (err.name !== 'AbortError') setError(err.message)
        })
        .finally(() => setLoading(false))
    }, DEBOUNCE_MS)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [swLat, swLng, neLat, neLng, searchQuery])

  useEffect(() => {
    const trimmedQuery = searchQuery.trim()
    if (trimmedQuery.length === 0) return
    let cancelled = false

    abortRef.current?.abort()
    abortRef.current = new AbortController()
    queueMicrotask(() => {
      if (!cancelled) setLoading(true)
    })

    const params = new URLSearchParams({
      query: trimmedQuery,
      transportation_type: transportationType!,
      travel_time_minutes: String(travelTimeMinutes!),
    })

    fetch(`/api/v1/properties/search?${params}`, { signal: abortRef.current.signal })
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
        setActiveLocationSearch({
          query: data.query,
          location: data.location,
          transportationType: data.transportation_type,
          travelTimeMinutes: Math.round(data.travel_time_seconds / 60),
          boundingBox: data.bounding_box,
          isochroneShells: data.isochrone_shells,
        })
        hasLoadedOnce.current = true
      })
      .catch(err => {
        if (err.name !== 'AbortError') setError(err.message)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
      abortRef.current?.abort()
    }
  }, [searchQuery, transportationType, travelTimeMinutes])

  return { properties, total, loading, error, activeLocationSearch }
}
