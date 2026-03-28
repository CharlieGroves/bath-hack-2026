import PropertyMap from './PropertyMap'
import { useProperties } from './hooks/useProperties'
import './App.css'

function App() {
  const { properties, loading, error } = useProperties()

  if (loading) return <p>Loading...</p>
  if (error) return <p>Error: {error}</p>

  return (
    <div style={{ height: '100vh', width: '100vw' }}>
      <PropertyMap properties={properties} />
    </div>
  )
}

export default App
