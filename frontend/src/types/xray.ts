export interface IsochroneCoord {
  latitude: number
  longitude: number
}

export interface Isochrone {
  minutes: number
  shells: IsochroneCoord[][]
}

export interface Poi {
  name: string
  amenity: string
  latitude: number
  longitude: number
  walk_minutes: number
}

export interface NearbySchool {
  id: number
  name: string
  urn: string
  p8mea: number | null
  latitude: number
  longitude: number
  distance_km: number
}

export interface XrayData {
  isochrones: Isochrone[]
  pois: Poi[]
  schools: NearbySchool[]
}
