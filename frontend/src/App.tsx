import PropertyMap from './PropertyMap'
import { useProperties } from './hooks/useProperties'
import './App.css'

function App() {
  const { properties, total, loading, error } = useProperties()

  const propertiesWithNoise = properties.filter((property) => property.noise?.status === 'ready').length

  if (loading) return <p>Loading...</p>
  if (error) return <p>Error: {error}</p>

  return (
    <div className="app-shell">
      <div className="status-panel">
        <h1>Bath Properties Noise Map</h1>
        <p>
          {total} properties loaded, {propertiesWithNoise} with stored noise data.
        </p>
      </div>
      <div className="map-shell">
        <PropertyMap properties={properties} />
      </div>
    </div>
  )
}

export default App
