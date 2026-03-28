import { useEffect, useState } from 'react'

// Each point is [lat, lng, normalised_intensity] where intensity is 0..1
export type HeatPoint = [number, number, number]

export interface HeatmapData {
  points: HeatPoint[]
  // Pounds per sq ft at each end of the scale (null until loaded)
  minPricePerSqft: number | null
  maxPricePerSqft: number | null
}

export function useHeatmapData(): HeatmapData {
  const [data, setData] = useState<HeatmapData>({
    points: [],
    minPricePerSqft: null,
    maxPricePerSqft: null,
  })

  useEffect(() => {
    fetch('/api/v1/properties/heatmap')
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then((res: { points: [number, number, number][] }) => {
        const raw = res.points
        if (!raw.length) return

        const sorted = [...raw.map(p => p[2])].sort((a, b) => a - b)
        const pct = (p: number) => sorted[Math.floor((sorted.length - 1) * p)]
        const lo = pct(0.05)
        const hi = pct(0.95)
        const range = hi - lo || 1

        setData({
          points: raw.map(([lat, lng, p]) => [lat, lng, Math.min(1, Math.max(0, (p - lo) / range))]),
          minPricePerSqft: Math.round(lo / 100),
          maxPricePerSqft: Math.round(hi / 100),
        })
      })
      .catch(() => {/* silently skip if endpoint unavailable */})
  }, [])

  return data
}
