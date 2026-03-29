import { useState } from 'react'
import { MapContainer, TileLayer, Marker, Polygon, CircleMarker, Popup } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import type { PropertyDetail } from '../types/property'
import type { XrayData, Isochrone, IsochroneCoord, NearbySchool } from '../types/xray'

// Isochrone bands: 5 min most opaque, 15 min most transparent
const ISOCHRONE_STYLES: Record<number, { fillOpacity: number; opacity: number }> = {
  5:  { fillOpacity: 0.18, opacity: 0.9 },
  10: { fillOpacity: 0.10, opacity: 0.7 },
  15: { fillOpacity: 0.05, opacity: 0.5 },
}

const AMENITY_COLOURS: Record<string, string> = {
  school:           '#3b82f6',  // blue
  supermarket:      '#16a34a',  // green
  convenience:      '#65a30d',  // lime
  bakery:           '#d97706',  // amber
  butcher:          '#b45309',  // brown
  greengrocer:      '#15803d',  // dark green
  newsagent:        '#9ca3af',  // grey
  department_store: '#16a34a',  // green
  pharmacy:         '#dc2626',  // red
  cafe:             '#78716c',  // stone
  station:          '#7c3aed',  // purple
  halt:             '#7c3aed',  // purple
}

function amenityColour(amenity: string): string {
  return AMENITY_COLOURS[amenity] ?? '#6b7280'
}

function fmtAmenity(amenity: string): string {
  return amenity.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
}

function shellToPositions(shell: IsochroneCoord[]): [number, number][] {
  return shell.map(p => [p.latitude, p.longitude])
}

interface Props {
  property: PropertyDetail
  xray: XrayData | null
  loading: boolean
}

function fmtP8mea(p8mea: number | null): string {
  if (p8mea == null) return 'No data'
  return (p8mea >= 0 ? '+' : '') + p8mea.toFixed(2)
}

function p8meaColour(p8mea: number | null): string {
  if (p8mea == null) return '#6b7280'
  if (p8mea >= 0.5) return '#16a34a'
  if (p8mea >= 0)   return '#65a30d'
  if (p8mea >= -0.5) return '#f59e0b'
  return '#dc2626'
}

export default function XrayMap({ property, xray, loading }: Props) {
  const [showRailLines, setShowRailLines] = useState(false)
  const [showSchools, setShowSchools] = useState(true)

  if (property.latitude == null || property.longitude == null) return null

  const pos: [number, number] = [Number(property.latitude), Number(property.longitude)]

  return (
    <div className="xray-map-wrap">
      <div className="xray-map-controls">
        <label className="xray-toggle">
          <input
            type="checkbox"
            checked={showRailLines}
            onChange={e => setShowRailLines(e.target.checked)}
          />
          Show train lines
        </label>
        <label className="xray-toggle">
          <input
            type="checkbox"
            checked={showSchools}
            onChange={e => setShowSchools(e.target.checked)}
          />
          Show schools
        </label>
        {loading && <span className="xray-loading-label">Loading neighbourhood data...</span>}
      </div>

      <MapContainer
        key={property.id}
        center={pos}
        zoom={15}
        style={{ height: '380px', width: '100%' }}
        zoomControl={true}
        attributionControl={true}
      >
        <TileLayer
          url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png"
          attribution='&copy; <a href="https://carto.com/">CARTO</a>'
        />

        {showRailLines && (
          <TileLayer
            url="https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png"
            attribution='&copy; <a href="https://www.openrailwaymap.org/">OpenRailwayMap</a> contributors, ODbL'
            opacity={0.6}
          />
        )}

        {xray?.isochrones.map((iso: Isochrone) => {
          const style = ISOCHRONE_STYLES[iso.minutes] ?? { fillOpacity: 0.05, opacity: 0.5 }
          return iso.shells.map((shell, i) => (
            <Polygon
              key={`iso-${iso.minutes}-${i}`}
              positions={shellToPositions(shell)}
              pathOptions={{
                color: '#E76814',
                weight: 1.5,
                opacity: style.opacity,
                fillColor: '#E76814',
                fillOpacity: style.fillOpacity,
              }}
            />
          ))
        })}

        {xray?.pois.map((poi, i) => (
          <CircleMarker
            key={i}
            center={[poi.latitude, poi.longitude]}
            radius={6}
            pathOptions={{
              color: amenityColour(poi.amenity),
              fillColor: amenityColour(poi.amenity),
              fillOpacity: 0.85,
              weight: 1.5,
            }}
          >
            <Popup>
              <div className="xray-poi-popup">
                <strong>{poi.name}</strong>
                <div>{fmtAmenity(poi.amenity)}</div>
                <div>{poi.walk_minutes} min walk</div>
              </div>
            </Popup>
          </CircleMarker>
        ))}

        {showSchools && xray?.schools.map((school: NearbySchool) => (
          <CircleMarker
            key={school.id}
            center={[school.latitude, school.longitude]}
            radius={8}
            pathOptions={{
              color: p8meaColour(school.p8mea),
              fillColor: p8meaColour(school.p8mea),
              fillOpacity: 0.85,
              weight: 2,
            }}
          >
            <Popup>
              <div className="xray-poi-popup">
                <strong>{school.name}</strong>
                <div>Progress 8: {fmtP8mea(school.p8mea)}</div>
                <div>{(school.distance_km * 1000).toFixed(0)}m away</div>
              </div>
            </Popup>
          </CircleMarker>
        ))}

        <Marker position={pos} />
      </MapContainer>

      {xray && xray.isochrones.length > 0 && (
        <div className="xray-legend">
          {xray.isochrones.map(iso => (
            <span key={iso.minutes} className="xray-legend-item">
              <span className="xray-legend-swatch" style={{ opacity: ISOCHRONE_STYLES[iso.minutes]?.fillOpacity ?? 0.05 }} />
              {iso.minutes} min walk
            </span>
          ))}
        </div>
      )}

      {xray && xray.pois.length > 0 && (
        <div className="xray-poi-list">
          <h3 className="xray-poi-heading">Nearby</h3>
          {xray.pois.slice(0, 12).map((poi, i) => (
            <div key={i} className="xray-poi-row">
              <span
                className="xray-poi-dot"
                style={{ backgroundColor: amenityColour(poi.amenity) }}
              />
              <span className="xray-poi-name">{poi.name}</span>
              <span className="xray-poi-type">{fmtAmenity(poi.amenity)}</span>
              <span className="xray-poi-time">{poi.walk_minutes} min</span>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
