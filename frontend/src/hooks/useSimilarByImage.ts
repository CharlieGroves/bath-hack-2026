import { useState, useRef } from 'react'
import type { Property } from '../types/property'

export interface SimilarMatch extends Property {
  image_similarity_distance: number
  matched_image_position: number
}

interface UseSimilarByImageResult {
  matches: SimilarMatch[]
  loading: boolean
  error: string | null
  fetchSimilar: (propertyId: number, position: number) => void
  clear: () => void
}

export function useSimilarByImage(): UseSimilarByImageResult {
  const [matches, setMatches] = useState<SimilarMatch[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  function fetchSimilar(propertyId: number, position: number) {
    abortRef.current?.abort()
    abortRef.current = new AbortController()
    setLoading(true)
    setError(null)
    setMatches([])

    fetch(
      `/api/v1/properties/similar_by_image?property_id=${propertyId}&position=${position}&k=6`,
      { signal: abortRef.current.signal },
    )
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json() as Promise<{ matches: SimilarMatch[] }>
      })
      .then(data => {
        setMatches(data.matches)
        setLoading(false)
      })
      .catch(e => {
        if (e.name !== 'AbortError') {
          setError(e.message)
          setLoading(false)
        }
      })
  }

  function clear() {
    abortRef.current?.abort()
    setMatches([])
    setError(null)
    setLoading(false)
  }

  return { matches, loading, error, fetchSimilar, clear }
}
