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

export interface XrayData {
  isochrones: Isochrone[]
  pois: Poi[]
}
