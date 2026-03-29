# Maps the raw borough strings returned by Nominatim reverse geocoding to the
# canonical names used in the NTE dataset (and stored in the boroughs table).
#
# Nominatim returns forms like "London Borough of Camden", "Royal Borough of
# Kensington and Chelsea", "City of Westminster", "City of London".  The NTE
# dataset uses plain names ("Camden", "Kensington and Chelsea", "Westminster",
# "City of London").
#
# Usage:
#   BoroughNameNormaliser.normalise("London Borough of Camden")  # => "Camden"
#   BoroughNameNormaliser.normalise("Unknown place")             # => nil
module BoroughNameNormaliser
  NOMINATIM_TO_CANONICAL = {
    "London Borough of Barking and Dagenham"    => "Barking and Dagenham",
    "London Borough of Barnet"                  => "Barnet",
    "London Borough of Bexley"                  => "Bexley",
    "London Borough of Brent"                   => "Brent",
    "London Borough of Bromley"                 => "Bromley",
    "London Borough of Camden"                  => "Camden",
    "City of London"                            => "City of London",
    "London Borough of Croydon"                 => "Croydon",
    "London Borough of Ealing"                  => "Ealing",
    "London Borough of Enfield"                 => "Enfield",
    "Royal Borough of Greenwich"                => "Greenwich",
    "London Borough of Hackney"                 => "Hackney",
    "London Borough of Hammersmith and Fulham"  => "Hammersmith and Fulham",
    "London Borough of Haringey"                => "Haringey",
    "London Borough of Harrow"                  => "Harrow",
    "London Borough of Havering"                => "Havering",
    "London Borough of Hillingdon"              => "Hillingdon",
    "London Borough of Hounslow"                => "Hounslow",
    "London Borough of Islington"               => "Islington",
    "Royal Borough of Kensington and Chelsea"   => "Kensington and Chelsea",
    "Royal Borough of Kingston upon Thames"     => "Kingston upon Thames",
    "London Borough of Lambeth"                 => "Lambeth",
    "London Borough of Lewisham"                => "Lewisham",
    "London Borough of Merton"                  => "Merton",
    "London Borough of Newham"                  => "Newham",
    "London Borough of Redbridge"               => "Redbridge",
    "London Borough of Richmond upon Thames"    => "Richmond upon Thames",
    "London Borough of Southwark"               => "Southwark",
    "London Borough of Sutton"                  => "Sutton",
    "London Borough of Tower Hamlets"           => "Tower Hamlets",
    "London Borough of Waltham Forest"          => "Waltham Forest",
    "London Borough of Wandsworth"              => "Wandsworth",
    "City of Westminster"                       => "Westminster"
  }.freeze

  # @param nominatim_name [String, nil]  raw string from Nominatim fifth-segment
  # @return [String, nil]  canonical borough name, or nil if not recognised
  def self.normalise(nominatim_name)
    return nil if nominatim_name.blank?
    NOMINATIM_TO_CANONICAL[nominatim_name.strip]
  end
end
