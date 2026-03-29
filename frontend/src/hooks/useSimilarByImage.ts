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
  fetchSimilar: (propertyId: number, position: number, textQuery?: string) => void
  fetchSimilarMaxpool: (propertyId: number, textQuery?: string) => void
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

  function fetchSimilar(propertyId: number, position: number, textQuery?: string) {
    startFetch()
    setActiveMode('per_photo')
    const params = new URLSearchParams({
      property_id: String(propertyId),
      position: String(position),
      k: '6',
    })
    if (textQuery) {
      params.set('text_query', textQuery)
      params.set('text_weight', '0.1')
    }
    fetch(
      `/api/v1/properties/similar_by_image?${params}`,
      { signal: abortRef.current!.signal },
    )
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<{ matches: SimilarMatch[] }>
      })
      .then(onSuccess)
      .catch(onError)
  }

  function fetchSimilarMaxpool(propertyId: number, textQuery?: string) {
    startFetch()
    setActiveMode('maxpool')
    const params = new URLSearchParams({
      property_id: String(propertyId),
      k: '6',
    })
    if (textQuery) {
      params.set('text_query', textQuery)
      params.set('text_weight', '0.1')
    }
    fetch(
      `/api/v1/properties/similar_by_image_maxpool?${params}`,
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
