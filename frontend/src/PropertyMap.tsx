import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L from 'leaflet'
import type { Property } from './types/property'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

delete (L.Icon.Default.prototype as any)._getIconUrl
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

export default function PropertyMap({
  properties,
  center = [51.38, -2.36], // Bath
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
              <strong>{p.title || p.address}</strong>
              <br />
              {p.address}
              <br />
              {p.price && formatPrice(p.price)}
              {p.bedrooms && ` · ${p.bedrooms} bed`}
            </Popup>
          </Marker>
        ))}
    </MapContainer>
  )
}
