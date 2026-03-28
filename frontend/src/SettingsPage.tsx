import { useRef } from 'react'
import LocationAutocompleteInput from './components/LocationAutocompleteInput'
import type { UserSettings } from './hooks/useSettings'
import './settings.css'

interface Props {
  settings: UserSettings
  updateSettings: (patch: Partial<UserSettings>) => void
  toggleItem: (key: keyof UserSettings, item: string) => void
  resetSettings: () => void
  onClose: () => void
}

const PROPERTY_TYPES = [
  { id: 'flat',          label: 'Flat' },
  { id: 'terraced',      label: 'Terraced' },
  { id: 'semi_detached', label: 'Semi-detached' },
  { id: 'detached',      label: 'Detached' },
  { id: 'bungalow',      label: 'Bungalow' },
  { id: 'land',          label: 'Land' },
]

const TENURES = [
  { id: 'freehold',           label: 'Freehold' },
  { id: 'leasehold',          label: 'Leasehold' },
  { id: 'share_of_freehold',  label: 'Share of freehold' },
]

const MUST_HAVES = [
  { id: 'garden',       label: 'Garden' },
  { id: 'parking',      label: 'Parking' },
  { id: 'garage',       label: 'Garage' },
  { id: 'new_build',    label: 'New build' },
  { id: 'period',       label: 'Period property' },
  { id: 'chain_free',   label: 'Chain free' },
  { id: 'ground_floor', label: 'Ground floor' },
  { id: 'top_floor',    label: 'Top floor' },
  { id: 'balcony',      label: 'Balcony / terrace' },
  { id: 'floor_plan',   label: 'Has floor plan' },
  { id: 'virtual_tour', label: 'Virtual tour' },
]

const SITUATIONS = [
  { id: 'first_time', label: 'First-time buyer' },
  { id: 'moving',     label: 'Moving home' },
  { id: 'investment', label: 'Buy to let / investment' },
  { id: 'let',        label: 'Looking to rent' },
]

const SECTIONS = [
  { id: 'budget',       label: 'Budget' },
  { id: 'requirements', label: 'Requirements' },
  { id: 'situation',    label: 'Situation' },
  { id: 'must_haves',   label: 'Must-haves' },
  { id: 'location',     label: 'Location & commute' },
  { id: 'display',      label: 'Display' },
]

export default function SettingsPage({ settings, updateSettings, toggleItem, resetSettings, onClose }: Props) {
  const sectionRefs = useRef<Record<string, HTMLElement | null>>({})

  function scrollTo(id: string) {
    sectionRefs.current[id]?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  return (
    <div className="sp-shell">
      {/* Left nav */}
      <nav className="sp-nav">
        <div className="sp-nav-brand">
          <svg width="18" height="22" viewBox="0 0 20 24" fill="none">
            <path d="M10 1C10 1 3 9 3 15.5a7 7 0 0014 0C17 9.5 10 1 10 1z" fill="#E76814"/>
            <path d="M10 9C10 9 7 13.5 7 16.5a3 3 0 006 0C13 13.5 10 9 10 9z" fill="#F25016"/>
          </svg>
          <span>Preferences</span>
        </div>
        <ul className="sp-nav-list">
          {SECTIONS.map(s => (
            <li key={s.id}>
              <button className="sp-nav-item" onClick={() => scrollTo(s.id)}>{s.label}</button>
            </li>
          ))}
        </ul>
        <div className="sp-nav-footer">
          <button className="sp-reset" onClick={resetSettings}>Reset all</button>
          <button className="sp-close" onClick={onClose}>Back to search</button>
        </div>
      </nav>

      {/* Content */}
      <div className="sp-content">
        <div className="sp-inner">

          {/* ── Budget ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['budget'] = el }}>
            <h2 className="sp-heading">Budget</h2>
            <p className="sp-sub">Set your price range. This will pre-fill the filters when you search.</p>
            <div className="sp-row">
              <div className="sp-field-wrap">
                <label className="sp-label">Minimum price</label>
                <div className="sp-price-box">
                  <span className="sp-prefix">£</span>
                  <input
                    className="sp-input"
                    type="number"
                    placeholder="No minimum"
                    value={settings.budgetMin}
                    onChange={e => updateSettings({ budgetMin: e.target.value === '' ? '' : +e.target.value })}
                  />
                </div>
              </div>
              <div className="sp-field-wrap">
                <label className="sp-label">Maximum price</label>
                <div className="sp-price-box">
                  <span className="sp-prefix">£</span>
                  <input
                    className="sp-input"
                    type="number"
                    placeholder="No maximum"
                    value={settings.budgetMax}
                    onChange={e => updateSettings({ budgetMax: e.target.value === '' ? '' : +e.target.value })}
                  />
                </div>
              </div>
            </div>
          </section>

          {/* ── Requirements ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['requirements'] = el }}>
            <h2 className="sp-heading">Requirements</h2>
            <p className="sp-sub">Narrow down property types and physical requirements.</p>

            <div className="sp-field-wrap" style={{ marginBottom: 20 }}>
              <label className="sp-label">Minimum bedrooms</label>
              <div className="sp-pill-row">
                {['', 1, 2, 3, 4, 5].map(n => (
                  <button
                    key={String(n)}
                    className={`sp-pill ${settings.minBeds === (n === '' ? '' : +n) ? 'sp-pill-on' : ''}`}
                    onClick={() => updateSettings({ minBeds: n === '' ? '' : +n })}
                  >{n === '' ? 'Any' : `${n}+`}</button>
                ))}
              </div>
            </div>

            <div className="sp-field-wrap" style={{ marginBottom: 20 }}>
              <label className="sp-label">Property type</label>
              <div className="sp-chip-grid">
                {PROPERTY_TYPES.map(t => (
                  <button
                    key={t.id}
                    className={`sp-chip ${settings.propertyTypes.includes(t.id) ? 'sp-chip-on' : ''}`}
                    onClick={() => toggleItem('propertyTypes', t.id)}
                  >{t.label}</button>
                ))}
              </div>
              {settings.propertyTypes.length === 0 && <p className="sp-hint">None selected — all types shown</p>}
            </div>

            <div className="sp-field-wrap" style={{ marginBottom: 20 }}>
              <label className="sp-label">Tenure</label>
              <div className="sp-chip-grid">
                {TENURES.map(t => (
                  <button
                    key={t.id}
                    className={`sp-chip ${settings.tenures.includes(t.id) ? 'sp-chip-on' : ''}`}
                    onClick={() => toggleItem('tenures', t.id)}
                  >{t.label}</button>
                ))}
              </div>
              {settings.tenures.length === 0 && <p className="sp-hint">None selected — all tenures shown</p>}
            </div>

            <div className="sp-field-wrap">
              <label className="sp-label">Minimum floor area (sq ft)</label>
              <input
                className="sp-text-input"
                type="number"
                placeholder="e.g. 700"
                value={settings.minSqft}
                onChange={e => updateSettings({ minSqft: e.target.value === '' ? '' : +e.target.value })}
                style={{ maxWidth: 180 }}
              />
            </div>
          </section>

          {/* ── Situation ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['situation'] = el }}>
            <h2 className="sp-heading">Your situation</h2>
            <p className="sp-sub">Helps us tailor how properties are presented to you.</p>
            <div className="sp-situation-grid">
              {SITUATIONS.map(s => (
                <button
                  key={s.id}
                  className={`sp-situation-btn ${settings.situation === s.id ? 'sp-situation-on' : ''}`}
                  onClick={() => updateSettings({ situation: settings.situation === s.id ? '' : s.id as UserSettings['situation'] })}
                >{s.label}</button>
              ))}
            </div>
          </section>

          {/* ── Must-haves ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['must_haves'] = el }}>
            <h2 className="sp-heading">Must-haves</h2>
            <p className="sp-sub">Features you won't compromise on.</p>
            <div className="sp-chip-grid">
              {MUST_HAVES.map(m => (
                <button
                  key={m.id}
                  className={`sp-chip ${settings.mustHaves.includes(m.id) ? 'sp-chip-on' : ''}`}
                  onClick={() => toggleItem('mustHaves', m.id)}
                >{m.label}</button>
              ))}
            </div>
            {settings.mustHaves.length > 0 && (
              <p className="sp-hint" style={{ marginTop: 10 }}>
                {settings.mustHaves.length} selected
              </p>
            )}
          </section>

          {/* ── Location & commute ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['location'] = el }}>
            <h2 className="sp-heading">Location & commute</h2>
            <p className="sp-sub">Preferred areas and your workplace address for commute calculations.</p>

            <div className="sp-field-wrap" style={{ marginBottom: 20 }}>
              <label className="sp-label">Preferred areas or postcodes</label>
              <LocationAutocompleteInput
                value={settings.preferredAreas}
                onChange={value => updateSettings({ preferredAreas: value })}
                inputClassName="sp-text-input"
                placeholder="e.g. Clifton, BA1 5, Larkhall"
              />
              <p className="sp-hint">Separate multiple areas with commas</p>
            </div>

            <div className="sp-field-wrap">
              <label className="sp-label">Workplace address or postcode</label>
              <LocationAutocompleteInput
                value={settings.workplace}
                onChange={value => updateSettings({ workplace: value })}
                inputClassName="sp-text-input"
                placeholder="e.g. Bath Spa Station, BS1 4DJ"
              />
              <p className="sp-hint">Used to estimate commute times on property listings</p>
            </div>
          </section>

          {/* ── Display ── */}
          <section className="sp-section" ref={el => { sectionRefs.current['display'] = el }}>
            <h2 className="sp-heading">Display</h2>
            <p className="sp-sub">Default sort order when you open the app.</p>
            <div className="sp-chip-grid">
              {[
                { id: 'newest',     label: 'Newest first' },
                { id: 'price_asc',  label: 'Price: low to high' },
                { id: 'price_desc', label: 'Price: high to low' },
                { id: 'beds_asc',   label: 'Fewest beds first' },
                { id: 'beds_desc',  label: 'Most beds first' },
              ].map(o => (
                <button
                  key={o.id}
                  className={`sp-chip ${settings.defaultSort === o.id ? 'sp-chip-on' : ''}`}
                  onClick={() => updateSettings({ defaultSort: o.id as UserSettings['defaultSort'] })}
                >{o.label}</button>
              ))}
            </div>
          </section>

        </div>
      </div>
    </div>
  )
}
