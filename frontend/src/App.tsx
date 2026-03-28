import type { FormEvent } from 'react'
import { useState } from 'react'
import PropertyMap from './PropertyMap'
import { useProperties } from './hooks/useProperties'
import './App.css'

const TRANSPORT_OPTIONS = [
  { value: 'driving', label: 'Driving' },
  { value: 'walking', label: 'Walking' },
  { value: 'cycling', label: 'Cycling' },
]

function formatCoordinate(value: number) {
  return value.toFixed(4)
}

function App() {
  const { properties, total, loading, searching, error, searchResult, searchByLocation, resetSearch } = useProperties()
  const [locationQuery, setLocationQuery] = useState('')
  const [transportationType, setTransportationType] = useState('driving')
  const [travelTimeMinutes, setTravelTimeMinutes] = useState(15)

  const propertiesWithNoise = properties.filter((property) => property.noise?.status === 'ready').length
  const hasActiveSearch = searchResult !== null
  const hasValidTravelTime = Number.isFinite(travelTimeMinutes) && travelTimeMinutes >= 1 && travelTimeMinutes <= 120
  const canSubmitSearch = locationQuery.trim().length > 0 && hasValidTravelTime && !searching

  async function handleSearchSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    await searchByLocation({
      query: locationQuery.trim(),
      transportationType,
      travelTimeMinutes,
    })
  }

  if (loading) {
    return (
      <div className="app-shell app-shell--centered">
        <p className="status-panel__loading">Loading properties...</p>
      </div>
    )
  }

  return (
    <div className="app-shell">
      <div className="status-panel">
        <p className="status-panel__eyebrow">TravelTime Isochrone Search</p>
        <h1>Bath Properties Noise Map</h1>
        <p className="status-panel__subtitle">
          Search a place, send it to the Rails backend, call TravelTime, then return the actual reachable area and
          only the properties inside it.
        </p>

        <form className="search-form" onSubmit={handleSearchSubmit}>
          <div className="search-form__field">
            <label htmlFor="location-query">Location</label>
            <input
              id="location-query"
              name="location-query"
              type="text"
              value={locationQuery}
              onChange={(event) => setLocationQuery(event.target.value)}
              placeholder="Bath Abbey, Bristol Temple Meads, BA1..."
            />
          </div>

          <div className="search-form__row">
            <div className="search-form__field">
              <label htmlFor="transportation-type">Mode</label>
              <select
                id="transportation-type"
                name="transportation-type"
                value={transportationType}
                onChange={(event) => setTransportationType(event.target.value)}
              >
                {TRANSPORT_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="search-form__field">
              <label htmlFor="travel-time-minutes">Minutes</label>
              <input
                id="travel-time-minutes"
                name="travel-time-minutes"
                type="number"
                min={1}
                max={120}
                step={1}
                value={travelTimeMinutes}
                onChange={(event) => setTravelTimeMinutes(Number(event.target.value) || 0)}
              />
            </div>
          </div>

          <div className="search-form__actions">
            <button className="search-button" type="submit" disabled={!canSubmitSearch}>
              {searching ? 'Searching...' : 'Run Search'}
            </button>
            {hasActiveSearch ? (
              <button className="clear-button" type="button" onClick={resetSearch}>
                Clear
              </button>
            ) : null}
          </div>
        </form>

        {error ? <p className="status-panel__error">{error}</p> : null}

        <div className="status-panel__stats">
          <p>
            {total} properties shown, {propertiesWithNoise} with stored noise data.
          </p>
          <p>{hasActiveSearch ? 'Filtered to the current TravelTime isochrone.' : 'Showing the full property set.'}</p>
        </div>

        {searchResult ? (
          <div className="search-summary">
            <p className="search-summary__label">{searchResult.location.label}</p>
            <p className="search-summary__meta">
              {searchResult.transportation_type} · {searchResult.travel_time_seconds / 60} min
            </p>
            <div className="search-summary__grid">
              <div className="search-summary__metric">
                <span>North</span>
                <strong>{formatCoordinate(searchResult.bounding_box.north)}</strong>
              </div>
              <div className="search-summary__metric">
                <span>South</span>
                <strong>{formatCoordinate(searchResult.bounding_box.south)}</strong>
              </div>
              <div className="search-summary__metric">
                <span>East</span>
                <strong>{formatCoordinate(searchResult.bounding_box.east)}</strong>
              </div>
              <div className="search-summary__metric">
                <span>West</span>
                <strong>{formatCoordinate(searchResult.bounding_box.west)}</strong>
              </div>
            </div>
          </div>
        ) : (
          <p className="status-panel__hint">
            The map will draw the TravelTime isochrone after you search and fit the viewport to the returned bounds.
          </p>
        )}
      </div>
      <div className="map-shell">
        <PropertyMap
          properties={properties}
          boundingBox={searchResult?.bounding_box ?? null}
          isochroneShells={searchResult?.isochrone_shells ?? null}
          searchLocation={searchResult?.location ?? null}
        />
      </div>
    </div>
  )
}

export default App
