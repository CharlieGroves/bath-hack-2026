import { useState, useRef, useCallback } from 'react'
import type { Property } from '../types/property'

export type ModelSearchStatus = 'idle' | 'pending' | 'complete' | 'failed'

export interface UseModelSearchResult {
  status: ModelSearchStatus
  prompt: string
  properties: Property[]
  error: string | null
  trigger: (prompt: string) => void
  clear: () => void
}

const POLL_INTERVAL_MS = 1200
const MAX_POLLS = 50

export function useModelSearch(): UseModelSearchResult {
  const [status, setStatus]         = useState<ModelSearchStatus>('idle')
  const [prompt, setPrompt]         = useState('')
  const [properties, setProperties] = useState<Property[]>([])
  const [error, setError]           = useState<string | null>(null)

  const pollTimerRef  = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pollCountRef  = useRef(0)
  const abortRef      = useRef<AbortController | null>(null)
  const activeIdRef   = useRef<number | null>(null)

  const stopPolling = useCallback(() => {
    if (pollTimerRef.current) {
      clearTimeout(pollTimerRef.current)
      pollTimerRef.current = null
    }
  }, [])

  const clear = useCallback(() => {
    stopPolling()
    abortRef.current?.abort()
    activeIdRef.current = null
    pollCountRef.current = 0
    setStatus('idle')
    setPrompt('')
    setProperties([])
    setError(null)
  }, [stopPolling])

  const poll = useCallback((id: number) => {
    if (id !== activeIdRef.current) return

    if (pollCountRef.current >= MAX_POLLS) {
      setStatus('failed')
      setError('Search timed out — please try again')
      return
    }

    pollCountRef.current++
    abortRef.current = new AbortController()

    fetch(`/api/v1/model_searches/${id}`, { signal: abortRef.current.signal })
      .then(async res => {
        const data = await res.json().catch(() => null)
        if (!res.ok) throw new Error(data?.error ?? `HTTP ${res.status}`)
        return data
      })
      .then(data => {
        if (id !== activeIdRef.current) return

        if (data.status === 'complete') {
          setProperties(data.properties ?? [])
          setStatus('complete')
          stopPolling()
        } else if (data.status === 'failed') {
          setError(data.error ?? 'Search failed')
          setStatus('failed')
          stopPolling()
        } else {
          pollTimerRef.current = setTimeout(() => poll(id), POLL_INTERVAL_MS)
        }
      })
      .catch(err => {
        if (err.name !== 'AbortError') {
          setError(err.message)
          setStatus('failed')
          stopPolling()
        }
      })
  }, [stopPolling])

  const trigger = useCallback((rawPrompt: string) => {
    const trimmed = rawPrompt.trim()
    if (!trimmed) return

    stopPolling()
    abortRef.current?.abort()
    activeIdRef.current = null
    pollCountRef.current = 0

    setPrompt(trimmed)
    setStatus('pending')
    setProperties([])
    setError(null)

    abortRef.current = new AbortController()

    fetch('/api/v1/model_searches', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: trimmed }),
      signal: abortRef.current.signal,
    })
      .then(async res => {
        const data = await res.json().catch(() => null)
        if (!res.ok) throw new Error(data?.error ?? `HTTP ${res.status}`)
        return data
      })
      .then(data => {
        activeIdRef.current = data.id
        pollTimerRef.current = setTimeout(() => poll(data.id), POLL_INTERVAL_MS)
      })
      .catch(err => {
        if (err.name !== 'AbortError') {
          setError(err.message)
          setStatus('failed')
        }
      })
  }, [stopPolling, poll])

  return { status, prompt, properties, error, trigger, clear }
}
