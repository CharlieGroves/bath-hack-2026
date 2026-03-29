import { useState, useEffect } from "react"
import type { XrayData } from "../types/xray"

interface UseXrayResult {
  xray: XrayData | null
  loading: boolean
  error: string | null
}

export function useXray(propertyId: number | null): UseXrayResult {
  const [xray, setXray] = useState<XrayData | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (propertyId == null) return

    let cancelled = false
    setLoading(true)
    setError(null)
    setXray(null)

    fetch(`/api/v1/properties/${propertyId}/xray`)
      .then(res => {
        if (!res.ok) throw new Error(`Xray request failed: ${res.status}`)
        return res.json()
      })
      .then((data: XrayData) => {
        if (!cancelled) setXray(data)
      })
      .catch(err => {
        if (!cancelled) setError(err.message)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => { cancelled = true }
  }, [propertyId])

  return { xray, loading, error }
}
