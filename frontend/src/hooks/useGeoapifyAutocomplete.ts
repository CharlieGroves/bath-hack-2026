import { useEffect, useRef, useState } from 'react'

const GEOAPIFY_API_KEY = import.meta.env.VITE_GEOAPIFY_API_KEY?.trim()
const MIN_QUERY_LENGTH = 3
const DEBOUNCE_MS = 220

interface GeoapifyAutocompleteResult {
  place_id?: string
  formatted?: string
  address_line1?: string
  address_line2?: string
  lat?: number
  lon?: number
  result_type?: string
}

interface GeoapifyAutocompleteResponse {
  results?: GeoapifyAutocompleteResult[]
}

export interface GeoapifySuggestion {
  id: string
  label: string
  secondaryLabel: string | null
  latitude: number | null
  longitude: number | null
  resultType: string | null
}

interface UseGeoapifyAutocompleteResult {
  suggestions: GeoapifySuggestion[]
  loading: boolean
  enabled: boolean
}

function toSuggestion(result: GeoapifyAutocompleteResult, index: number): GeoapifySuggestion | null {
  const label = result.formatted?.trim() || result.address_line1?.trim()
  if (!label) return null

  const secondaryLabel = result.address_line2?.trim()

  return {
    id: result.place_id ?? `${label}-${index}`,
    label,
    secondaryLabel: secondaryLabel && secondaryLabel !== label ? secondaryLabel : null,
    latitude: typeof result.lat === 'number' ? result.lat : null,
    longitude: typeof result.lon === 'number' ? result.lon : null,
    resultType: result.result_type?.trim() || null,
  }
}

export function useGeoapifyAutocomplete(query: string): UseGeoapifyAutocompleteResult {
  const [suggestions, setSuggestions] = useState<GeoapifySuggestion[]>([])
  const [loading, setLoading] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    const trimmedQuery = query.trim()
    const enabled = Boolean(GEOAPIFY_API_KEY)

    if (!enabled || trimmedQuery.length < MIN_QUERY_LENGTH) {
      abortRef.current?.abort()
      if (timerRef.current) clearTimeout(timerRef.current)
      queueMicrotask(() => {
        setSuggestions([])
        setLoading(false)
      })
      return
    }

    if (timerRef.current) clearTimeout(timerRef.current)

    timerRef.current = setTimeout(() => {
      abortRef.current?.abort()
      const controller = new AbortController()
      abortRef.current = controller
      setLoading(true)

      const params = new URLSearchParams({
        text: trimmedQuery,
        format: 'json',
        lang: 'en',
        limit: '6',
        apiKey: GEOAPIFY_API_KEY!,
      })

      fetch(`https://api.geoapify.com/v1/geocode/autocomplete?${params.toString()}`, {
        signal: controller.signal,
      })
        .then(async response => {
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          return response.json() as Promise<GeoapifyAutocompleteResponse>
        })
        .then(data => {
          const nextSuggestions = (data.results ?? [])
            .map(toSuggestion)
            .filter((suggestion): suggestion is GeoapifySuggestion => suggestion != null)

          setSuggestions(nextSuggestions)
        })
        .catch(error => {
          if (error.name !== 'AbortError') setSuggestions([])
        })
        .finally(() => {
          if (!controller.signal.aborted) setLoading(false)
        })
    }, DEBOUNCE_MS)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      abortRef.current?.abort()
    }
  }, [query])

  return {
    suggestions,
    loading,
    enabled: Boolean(GEOAPIFY_API_KEY),
  }
}
