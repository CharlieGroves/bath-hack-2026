import { useState, useEffect } from 'react'

export interface UserSettings {
  // Budget
  budgetMin: number | ''
  budgetMax: number | ''

  // Property requirements
  minBeds: number | ''
  propertyTypes: string[]
  tenures: string[]
  minSqft: number | ''

  // Situation
  situation: 'first_time' | 'moving' | 'investment' | 'let' | ''

  // Must-haves
  mustHaves: string[]

  // Location / commute
  preferredAreas: string
  workplace: string

  // Display defaults
  defaultSort: 'newest' | 'price_asc' | 'price_desc' | 'beds_asc' | 'beds_desc'
}

export const DEFAULT_SETTINGS: UserSettings = {
  budgetMin: '',
  budgetMax: '',
  minBeds: '',
  propertyTypes: [],
  tenures: [],
  minSqft: '',
  situation: '',
  mustHaves: [],
  preferredAreas: '',
  workplace: '',
  defaultSort: 'newest',
}

const STORAGE_KEY = 'hestia_settings'

export function useSettings() {
  const [settings, setSettings] = useState<UserSettings>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      return stored ? { ...DEFAULT_SETTINGS, ...JSON.parse(stored) } : DEFAULT_SETTINGS
    } catch {
      return DEFAULT_SETTINGS
    }
  })

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
  }, [settings])

  function updateSettings(patch: Partial<UserSettings>) {
    setSettings(s => ({ ...s, ...patch }))
  }

  function toggleItem<K extends keyof UserSettings>(key: K, item: string) {
    setSettings(s => {
      const arr = s[key] as string[]
      return {
        ...s,
        [key]: arr.includes(item) ? arr.filter(x => x !== item) : [...arr, item],
      }
    })
  }

  function resetSettings() {
    setSettings(DEFAULT_SETTINGS)
  }

  return { settings, updateSettings, toggleItem, resetSettings }
}
