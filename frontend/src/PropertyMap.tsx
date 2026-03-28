import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import type { NoiseSection, Property } from './types/property'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

type LeafletDefaultIconPrototype = { _getIconUrl?: string }

delete (L.Icon.Default.prototype as LeafletDefaultIconPrototype)._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
})

interface PropertyMapProps {
  properties: Property[]
  center?: [number, number]
  zoom?: number
}

function formatPrice(pence: number) {
  return `£${(pence / 100).toLocaleString('en-GB')}`
}

function formatNoiseMetric(section: NoiseSection | undefined, metric: string) {
  const value = section?.metrics?.[metric]
  return typeof value === 'number' ? `${value.toFixed(1)} dB` : 'No data'
}

export default function PropertyMap({
  properties,
  center = [51.5074, -0.1278], // London
  zoom = 13,
}: PropertyMapProps) {
  return (
    <MapContainer center={center} zoom={zoom} style={{ height: '100%', width: '100%' }}>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {properties
        .filter((p) => p.latitude != null && p.longitude != null)
        .map((p) => (
          <Marker key={p.id} position={[p.latitude, p.longitude]}>
            <Popup>
              <h2 className="popup-title">{p.title || p.address}</h2>
              <p className="popup-address">{p.address}</p>
              <p className="popup-price">
                {p.price && formatPrice(p.price)}
                {p.bedrooms && ` · ${p.bedrooms} bed`}
              </p>
              {p.noise ? (
                <>
                  <p className="popup-noise-status">
                    Noise snapshot: {p.noise.status}
                  </p>
                  <ul className="popup-noise-list">
                    <li>Road Lden: {formatNoiseMetric(p.noise.road_data, 'lden')}</li>
                    <li>Rail Lden: {formatNoiseMetric(p.noise.rail_data, 'lden')}</li>
                    <li>Flight Lden: {formatNoiseMetric(p.noise.flight_data, 'lden')}</li>
                    <li>Road LAeq16hr: {formatNoiseMetric(p.noise.road_data, 'laeq16hr')}</li>
                    <li>Rail LAeq16hr: {formatNoiseMetric(p.noise.rail_data, 'laeq16hr')}</li>
                    <li>Flight LAeq16hr: {formatNoiseMetric(p.noise.flight_data, 'laeq16hr')}</li>
                  </ul>
                </>
              ) : (
                <p className="popup-noise-empty">Noise snapshot not loaded yet.</p>
              )}
            </Popup>
          </Marker>
        ))}
    </MapContainer>
  )
}
