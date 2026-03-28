import { useEffect, useRef, useState } from 'react'

const MIN_QUERY_LENGTH = 3
const DEBOUNCE_MS = 220

interface GeoapifyAutocompleteResponse {
  enabled?: boolean
  suggestions?: Array<{
    id?: string
    label?: string
    secondary_label?: string | null
    latitude?: number | null
    longitude?: number | null
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

function toSuggestion(result: NonNullable<GeoapifyAutocompleteResponse["suggestions"]>[number], index: number): GeoapifySuggestion | null {
  const label = result.label?.trim()
  if (!label) return null

  const secondaryLabel = result.secondary_label?.trim()

  return {
    id: result.id ?? `${label}-${index}`,
    label,
    secondaryLabel: secondaryLabel && secondaryLabel !== label ? secondaryLabel : null,
    latitude: typeof result.latitude === 'number' ? result.latitude : null,
    longitude: typeof result.longitude === 'number' ? result.longitude : null,
    resultType: result.result_type?.trim() || null,
  }
}

export function useGeoapifyAutocomplete(query: string): UseGeoapifyAutocompleteResult {
  const [suggestions, setSuggestions] = useState<GeoapifySuggestion[]>([])
  const [loading, setLoading] = useState(false)
  const [enabled, setEnabled] = useState(true)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    const trimmedQuery = query.trim()

    if (trimmedQuery.length < MIN_QUERY_LENGTH) {
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

      const params = new URLSearchParams({ query: trimmedQuery })

      fetch(`/api/v1/location_autocomplete?${params.toString()}`, {
        signal: controller.signal,
      })
        .then(async response => {
          const payload = await response.json().catch(() => null) as GeoapifyAutocompleteResponse | null
          if (!response.ok) {
            if (payload?.enabled === false) setEnabled(false)
            throw new Error(`HTTP ${response.status}`)
          }

          return payload
        })
        .then(data => {
          setEnabled(data?.enabled !== false)

          const nextSuggestions = (data?.suggestions ?? [])
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
    enabled,
  }
}
