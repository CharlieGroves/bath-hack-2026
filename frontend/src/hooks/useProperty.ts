import { useEffect, useState, useRef } from 'react'
import type { PropertyDetail } from '../types/property'

interface UsePropertyResult {
  property: PropertyDetail | null
  loading: boolean
  error: string | null
}

export function useProperty(id: number | null): UsePropertyResult {
  const [property, setProperty] = useState<PropertyDetail | null>(null)
  const [resolvedId, setResolvedId] = useState<number | null>(null)
  const [errorState, setErrorState] = useState<{ id: number; message: string } | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    if (id === null) return

    abortRef.current?.abort()
    abortRef.current = new AbortController()

    fetch(`/api/v1/properties/${id}`, { signal: abortRef.current.signal })
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<PropertyDetail>
      })
      .then(data => {
        setProperty(data)
        setResolvedId(id)
        setErrorState(null)
      })
      .catch(e => {
        if (e.name !== 'AbortError') {
          setResolvedId(id)
          setErrorState({ id, message: e.message })
        }
      })

    return () => {
      abortRef.current?.abort()
    }
  }, [id])

  const loading = id !== null && resolvedId !== id
  const error = id === null || errorState?.id !== id ? null : errorState.message
  const resolvedProperty = id === null || resolvedId !== id || error ? null : property

  return {
    property: resolvedProperty,
    loading,
    error,
  }
}
