# frozen_string_literal: true

# Only formats persisted data; provider calls belong to the geocoding worker.
class Families::LocationAddress
  def self.call(point)
    data = point.geodata.is_a?(Hash) ? point.geodata : {}
    properties = data['properties'].is_a?(Hash) ? data['properties'] : {}
    address = data['address'].is_a?(Hash) ? data['address'] : {}
    parts = properties.empty? ? address : properties

    street = text(parts['street'], parts['road'], parts['pedestrian'], parts['highway'])
    house = text(parts['housenumber'], parts['house_number'])
    locality = text(parts['city'], parts['town'], parts['village'], parts['hamlet'], point.city)
    country = text(parts['country'], point.country_name)
    street_line = [street, house].compact.join(' ') if street
    result = [street_line, locality, country].compact.uniq.join(', ')
    result.empty? ? nil : result
  end

  def self.text(*values)
    values.find { |value| value.is_a?(String) && !value.strip.empty? }&.strip
  end
  private_class_method :text
end
