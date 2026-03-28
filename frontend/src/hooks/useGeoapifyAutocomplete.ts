import { useEffect, useRef, useState } from 'react'

const GEOAPIFY_API_KEY = import.meta.env.VITE_GEOAPIFY_API_KEY?.trim() ?? ''
const GEOAPIFY_AUTOCOMPLETE_URL = 'https://api.geoapify.com/v1/geocode/autocomplete'
const MIN_QUERY_LENGTH = 3
const DEBOUNCE_MS = 220

interface GeoapifyApiResponse {
  results?: Array<{
    place_id?: string
    formatted?: string
    address_line1?: string | null
    address_line2?: string | null
    lat?: number | string | null
    lon?: number | string | null
    result_type?: string | null
  }>
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

function numericOrNull(value: number | string | null | undefined): number | null {
  if (value == null) return null

  const numericValue = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(numericValue) ? numericValue : null
}

function toSuggestion(result: NonNullable<GeoapifyApiResponse['results']>[number], index: number): GeoapifySuggestion | null {
  const label = result.formatted?.trim() || result.address_line1?.trim() || ''
  if (!label) return null

  const secondaryLabel = result.address_line2?.trim()

  return {
    id: result.place_id ?? `${label}-${index}`,
    label,
    secondaryLabel: secondaryLabel && secondaryLabel !== label ? secondaryLabel : null,
    latitude: numericOrNull(result.lat),
    longitude: numericOrNull(result.lon),
    resultType: result.result_type?.trim() || null,
  }
}

export function useGeoapifyAutocomplete(query: string): UseGeoapifyAutocompleteResult {
  const enabled = GEOAPIFY_API_KEY.length > 0
  const [suggestions, setSuggestions] = useState<GeoapifySuggestion[]>([])
  const [loading, setLoading] = useState(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    const trimmedQuery = query.trim()

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
        apiKey: GEOAPIFY_API_KEY,
        format: 'json',
        lang: 'en',
        limit: '6',
      })

      fetch(`${GEOAPIFY_AUTOCOMPLETE_URL}?${params.toString()}`, {
        signal: controller.signal,
      })
        .then(async response => {
          const payload = await response.json().catch(() => null) as GeoapifyApiResponse | null
          if (!response.ok) throw new Error(`HTTP ${response.status}`)
          return payload
        })
        .then(data => {
          const nextSuggestions = (data?.results ?? [])
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
  }, [enabled, query])

  return {
    suggestions,
    loading,
    enabled,
  }
}
