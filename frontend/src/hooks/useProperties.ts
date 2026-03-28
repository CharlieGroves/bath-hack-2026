import { useEffect, useState, useRef } from 'react'
import type { Property } from '../types/property'

export interface MapBounds {
  sw_lat: number
  sw_lng: number
  ne_lat: number
  ne_lng: number
}

interface UsePropertiesResult {
  properties: Property[]
  total: number
  loading: boolean
  error: string | null
}

// Debounce delay in ms — avoids hammering the API while the map is mid-drag
const DEBOUNCE_MS = 300

export function useProperties(bounds: MapBounds | null): UsePropertiesResult {
  const [properties, setProperties] = useState<Property[]>([])
  const [total, setTotal]           = useState(0)
  const [loading, setLoading]       = useState(false)
  const [error, setError]           = useState<string | null>(null)

  const abortRef      = useRef<AbortController | null>(null)
  const timerRef      = useRef<ReturnType<typeof setTimeout> | null>(null)
  const hasLoadedOnce = useRef(false)

  useEffect(() => {
    if (!bounds) return

    // Debounce
    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      // Cancel any in-flight request
      abortRef.current?.abort()
      abortRef.current = new AbortController()

      const params = new URLSearchParams({
        sw_lat: String(bounds.sw_lat),
        sw_lng: String(bounds.sw_lng),
        ne_lat: String(bounds.ne_lat),
        ne_lng: String(bounds.ne_lng),
      })

      if (!hasLoadedOnce.current) setLoading(true)
      fetch(`/api/v1/properties?${params}`, { signal: abortRef.current.signal })
        .then(res => {
          if (!res.ok) throw new Error(`HTTP ${res.status}`)
          return res.json()
        })
        .then(data => {
          setProperties(data.properties)
          setTotal(data.total)
          setError(null)
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
  }, [bounds?.sw_lat, bounds?.sw_lng, bounds?.ne_lat, bounds?.ne_lng])

  return { properties, total, loading, error }
}
