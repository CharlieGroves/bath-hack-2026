import { useEffect, useState } from 'react'
import type { Property } from '../types/property'

interface UsePropertiesResult {
  properties: Property[]
  total: number
  loading: boolean
  error: string | null
}

export function useProperties(): UsePropertiesResult {
  const [properties, setProperties] = useState<Property[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/api/v1/properties')
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        return res.json()
      })
      .then((data) => {
        setProperties(data.properties)
        setTotal(data.total)
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }, [])

  return { properties, total, loading, error }
}
