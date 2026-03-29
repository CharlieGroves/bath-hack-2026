import { useState, useRef } from 'react'
import type { Property } from '../types/property'

export interface SimilarMatch extends Property {
  image_similarity_distance?: number
  matched_image_position?: number
  pooled_image_similarity_distance?: number
}

export type SimilarMode = 'per_photo' | 'maxpool'

interface UseSimilarByImageResult {
  matches: SimilarMatch[]
  loading: boolean
  error: string | null
  activeMode: SimilarMode | null
  fetchSimilar: (propertyId: number, position: number) => void
  fetchSimilarMaxpool: (propertyId: number) => void
  clear: () => void
}

export function useSimilarByImage(): UseSimilarByImageResult {
  const [matches, setMatches] = useState<SimilarMatch[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [activeMode, setActiveMode] = useState<SimilarMode | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  function startFetch() {
    abortRef.current?.abort()
    abortRef.current = new AbortController()
    setLoading(true)
    setError(null)
    setMatches([])
  }

  function onSuccess(data: { matches: SimilarMatch[] }) {
    setMatches(data.matches)
    setLoading(false)
  }

  function onError(e: Error) {
    if (e.name !== 'AbortError') {
      setError(e.message)
      setLoading(false)
    }
  }

  function fetchSimilar(propertyId: number, position: number) {
    startFetch()
    setActiveMode('per_photo')
    fetch(
      `/api/v1/properties/similar_by_image?property_id=${propertyId}&position=${position}&k=6`,
      { signal: abortRef.current!.signal },
    )
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<{ matches: SimilarMatch[] }>
      })
      .then(onSuccess)
      .catch(onError)
  }

  function fetchSimilarMaxpool(propertyId: number) {
    startFetch()
    setActiveMode('maxpool')
    fetch(
      `/api/v1/properties/similar_by_image_maxpool?property_id=${propertyId}&k=6`,
      { signal: abortRef.current!.signal },
    )
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<{ matches: SimilarMatch[] }>
      })
      .then(onSuccess)
      .catch(onError)
  }

  function clear() {
    abortRef.current?.abort()
    setMatches([])
    setError(null)
    setLoading(false)
    setActiveMode(null)
  }

  return { matches, loading, error, activeMode, fetchSimilar, fetchSimilarMaxpool, clear }
}
