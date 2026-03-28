import 'leaflet'

declare module 'leaflet' {
  interface HeatLayerOptions {
    radius?: number
    blur?: number
    maxZoom?: number
    max?: number
    gradient?: Record<number, string>
  }

  function heatLayer(
    latlngs: ReadonlyArray<[number, number, number?]>,
    options?: HeatLayerOptions,
  ): Layer
}

declare module 'leaflet.heat'
