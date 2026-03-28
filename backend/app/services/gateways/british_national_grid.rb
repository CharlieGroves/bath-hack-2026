class BritishNationalGrid
  WGS84_A = 6_378_137.0
  WGS84_B = 6_356_752.314245
  AIRY1830_A = 6_377_563.396
  AIRY1830_B = 6_356_256.909

  def self.from_wgs84(latitude, longitude)
    lat = degrees_to_radians(latitude)
    lon = degrees_to_radians(longitude)
    x1, y1, z1 = lat_lon_to_cartesian(lat, lon, WGS84_A, WGS84_B)
    x2, y2, z2 = helmert_transform(x1, y1, z1)
    lat_osgb, lon_osgb = cartesian_to_lat_lon(x2, y2, z2, AIRY1830_A, AIRY1830_B)
    lat_lon_to_grid(lat_osgb, lon_osgb)
  end

  def self.degrees_to_radians(value)
    value * Math::PI / 180
  end

  def self.lat_lon_to_cartesian(lat, lon, a, b)
    e2 = 1 - ((b * b) / (a * a))
    sin_lat = Math.sin(lat)
    cos_lat = Math.cos(lat)
    sin_lon = Math.sin(lon)
    cos_lon = Math.cos(lon)
    v = a / Math.sqrt(1 - (e2 * sin_lat * sin_lat))

    [
      v * cos_lat * cos_lon,
      v * cos_lat * sin_lon,
      v * (1 - e2) * sin_lat
    ]
  end

  def self.helmert_transform(x, y, z)
    tx = -446.448
    ty = 125.157
    tz = -542.06
    rx = degrees_to_radians(-0.1502 / 3600)
    ry = degrees_to_radians(-0.2470 / 3600)
    rz = degrees_to_radians(-0.8421 / 3600)
    scale = 20.4894 * 1e-6 + 1

    [
      tx + (x * scale) - (y * rz) + (z * ry),
      ty + (x * rz) + (y * scale) - (z * rx),
      tz - (x * ry) + (y * rx) + (z * scale)
    ]
  end

  def self.cartesian_to_lat_lon(x, y, z, a, b)
    e2 = 1 - ((b * b) / (a * a))
    p = Math.sqrt((x * x) + (y * y))
    lat = Math.atan2(z, p * (1 - e2))

    loop do
      v = a / Math.sqrt(1 - (e2 * Math.sin(lat)**2))
      next_lat = Math.atan2(z + (e2 * v * Math.sin(lat)), p)
      if (next_lat - lat).abs < 1e-12
        lat = next_lat
        break
      end

      lat = next_lat
    end

    [lat, Math.atan2(y, x)]
  end

  def self.lat_lon_to_grid(lat, lon)
    f0 = 0.9996012717
    lat0 = degrees_to_radians(49)
    lon0 = degrees_to_radians(-2)
    n0 = -100_000
    e0 = 400_000
    e2 = 1 - ((AIRY1830_B * AIRY1830_B) / (AIRY1830_A * AIRY1830_A))
    n = (AIRY1830_A - AIRY1830_B) / (AIRY1830_A + AIRY1830_B)
    sin_lat = Math.sin(lat)
    cos_lat = Math.cos(lat)
    tan_lat = Math.tan(lat)
    nu = AIRY1830_A * f0 / Math.sqrt(1 - (e2 * sin_lat * sin_lat))
    rho = AIRY1830_A * f0 * (1 - e2) / ((1 - (e2 * sin_lat * sin_lat))**1.5)
    eta2 = (nu / rho) - 1
    m = meridional_arc(lat, lat0, n, f0)
    d_lon = lon - lon0
    i = m + n0
    ii = (nu / 2) * sin_lat * cos_lat
    iii = (nu / 24) * sin_lat * (cos_lat**3) * (5 - (tan_lat**2) + (9 * eta2))
    iiia = (nu / 720) * sin_lat * (cos_lat**5) * (61 - (58 * tan_lat**2) + (tan_lat**4))
    iv = nu * cos_lat
    v = (nu / 6) * (cos_lat**3) * ((nu / rho) - (tan_lat**2))
    vi = (nu / 120) * (cos_lat**5) * (5 - (18 * tan_lat**2) + (tan_lat**4) + (14 * eta2) - (58 * tan_lat**2 * eta2))
    northing = i + (ii * d_lon**2) + (iii * d_lon**4) + (iiia * d_lon**6)
    easting = e0 + (iv * d_lon) + (v * d_lon**3) + (vi * d_lon**5)

    [easting, northing]
  end

  def self.meridional_arc(lat, lat0, n, f0)
    ma = (1 + n + ((5.0 / 4.0) * n**2) + ((5.0 / 4.0) * n**3)) * (lat - lat0)
    mb = ((3 * n) + (3 * n**2) + ((21.0 / 8.0) * n**3)) * Math.sin(lat - lat0) * Math.cos(lat + lat0)
    mc = (((15.0 / 8.0) * n**2) + ((15.0 / 8.0) * n**3)) * Math.sin(2 * (lat - lat0)) * Math.cos(2 * (lat + lat0))
    md = (35.0 / 24.0) * n**3 * Math.sin(3 * (lat - lat0)) * Math.cos(3 * (lat + lat0))

    AIRY1830_B * f0 * (ma - mb + mc - md)
  end
end
