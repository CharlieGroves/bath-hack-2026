import { useEffect, useState, useRef } from 'react'
import type { PropertyDetail } from '../types/property'

interface UsePropertyResult {
  property: PropertyDetail | null
  loading: boolean
  error: string | null
}

export function useProperty(id: number | null): UsePropertyResult {
  const [property, setProperty] = useState<PropertyDetail | null>(null)
  const [loading, setLoading]   = useState(false)
  const [error, setError]       = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    if (id === null) {
      setProperty(null)
      return
    }

    abortRef.current?.abort()
    abortRef.current = new AbortController()

    setLoading(true)
    setError(null)

    fetch(`/api/v1/properties/${id}`, { signal: abortRef.current.signal })
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<PropertyDetail>
      })
      .then(data => {
        setProperty(data)
        setError(null)
      })
      .catch(e => {
        if (e.name !== 'AbortError') setError(e.message)
      })
      .finally(() => setLoading(false))

    return () => {
      abortRef.current?.abort()
    }
  }, [id])

  return { property, loading, error }
}
