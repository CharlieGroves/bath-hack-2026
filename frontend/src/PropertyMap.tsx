import { useEffect } from 'react'
import { CircleMarker, MapContainer, Marker, Polygon, Popup, TileLayer, useMap } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import L, { type LatLngBoundsExpression } from 'leaflet'
import type { BoundingBox, IsochroneCoordinate, NoiseSection, Property, SearchLocation } from './types/property'

// Fix default marker icons broken by Vite's asset pipeline
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png'
import markerIcon from 'leaflet/dist/images/marker-icon.png'
import markerShadow from 'leaflet/dist/images/marker-shadow.png'

type LeafletDefaultIconPrototype = typeof L.Icon.Default.prototype & {
  _getIconUrl?: string
}

delete (L.Icon.Default.prototype as LeafletDefaultIconPrototype)._getIconUrl
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
})

interface PropertyMapProps {
  properties: Property[]
  boundingBox?: BoundingBox | null
  isochroneShells?: IsochroneCoordinate[][] | null
  searchLocation?: SearchLocation | null
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

function propertyCoordinates(property: Property): [number, number] | null {
  const latitude = Number(property.latitude)
  const longitude = Number(property.longitude)

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return null
  }

  return [latitude, longitude]
}

function rectangleBounds(boundingBox: BoundingBox): LatLngBoundsExpression {
  return [
    [boundingBox.south, boundingBox.west],
    [boundingBox.north, boundingBox.east],
  ]
}

function polygonPositions(shell: IsochroneCoordinate[]): [number, number][] {
  return shell.map((coordinate) => [coordinate.latitude, coordinate.longitude])
}

function MapViewportController({
  boundingBox,
  searchLocation,
  defaultCenter,
  defaultZoom,
}: {
  boundingBox: BoundingBox | null | undefined
  searchLocation: SearchLocation | null | undefined
  defaultCenter: [number, number]
  defaultZoom: number
}) {
  const map = useMap()
  const defaultLatitude = defaultCenter[0]
  const defaultLongitude = defaultCenter[1]

  useEffect(() => {
    if (boundingBox) {
      map.fitBounds(rectangleBounds(boundingBox), {
        padding: [36, 36],
      })
      return
    }

    if (searchLocation) {
      map.setView([searchLocation.latitude, searchLocation.longitude], defaultZoom)
      return
    }

    map.setView([defaultLatitude, defaultLongitude], defaultZoom)
  }, [boundingBox, defaultLatitude, defaultLongitude, defaultZoom, map, searchLocation])

  return null
}

export default function PropertyMap({
  properties,
  boundingBox,
  isochroneShells,
  searchLocation,
  center = [51.38, -2.36], // Bath
  zoom = 13,
}: PropertyMapProps) {
  return (
    <MapContainer center={center} zoom={zoom} style={{ height: '100%', width: '100%' }}>
      <MapViewportController
        boundingBox={boundingBox}
        searchLocation={searchLocation}
        defaultCenter={center}
        defaultZoom={zoom}
      />
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {isochroneShells?.map((shell, index) => (
        <Polygon
          key={`isochrone-shell-${index}`}
          positions={polygonPositions(shell)}
          pathOptions={{
            color: '#136f63',
            fillColor: '#7dd3c7',
            fillOpacity: 0.18,
            weight: 2,
          }}
        />
      ))}
      {searchLocation ? (
        <CircleMarker
          center={[searchLocation.latitude, searchLocation.longitude]}
          radius={7}
          pathOptions={{
            color: '#8f1d21',
            fillColor: '#d94841',
            fillOpacity: 0.9,
            weight: 2,
          }}
        >
          <Popup>
            <h2 className="popup-title">Search Origin</h2>
            <p className="popup-address">{searchLocation.label}</p>
          </Popup>
        </CircleMarker>
      ) : null}
      {properties
        .map((property) => {
          const coordinates = propertyCoordinates(property)
          if (!coordinates) return null

          return (
            <Marker key={property.id} position={coordinates}>
              <Popup>
                <h2 className="popup-title">{property.title || property.address}</h2>
                <p className="popup-address">{property.address}</p>
                <p className="popup-price">
                  {property.price && formatPrice(property.price)}
                  {property.bedrooms && ` · ${property.bedrooms} bed`}
                </p>
                {property.noise ? (
                  <>
                    <p className="popup-noise-status">
                      Noise snapshot: {property.noise.status}
                    </p>
                    <ul className="popup-noise-list">
                      <li>Road Lden: {formatNoiseMetric(property.noise.road_data, 'lden')}</li>
                      <li>Rail Lden: {formatNoiseMetric(property.noise.rail_data, 'lden')}</li>
                      <li>Flight Lden: {formatNoiseMetric(property.noise.flight_data, 'lden')}</li>
                      <li>Road LAeq16hr: {formatNoiseMetric(property.noise.road_data, 'laeq16hr')}</li>
                      <li>Rail LAeq16hr: {formatNoiseMetric(property.noise.rail_data, 'laeq16hr')}</li>
                      <li>Flight LAeq16hr: {formatNoiseMetric(property.noise.flight_data, 'laeq16hr')}</li>
                    </ul>
                  </>
                ) : (
                  <p className="popup-noise-empty">Noise snapshot not loaded yet.</p>
                )}
              </Popup>
            </Marker>
          )
        })}
    </MapContainer>
  )
}
