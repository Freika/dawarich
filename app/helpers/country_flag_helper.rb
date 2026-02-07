# frozen_string_literal: true

module CountryFlagHelper
  # User-assigned codes for territories with iso_a2 = "-99" in Natural Earth data.
  # Only includes territories that have a corresponding flag SVG in flag-icons.
  TERRITORY_CODES = {
    'Kosovo' => 'XK',
    'Somaliland' => 'SO',
    'Northern Cyprus' => 'CY'
  }.freeze

  def country_flag(country_name)
    country_code = country_to_code(country_name)
    return '' unless country_code

    country_code = 'TW' if country_code == 'CN-TW'

    # Resolve -99 territories via name lookup
    if country_code == '-99'
      country_code = TERRITORY_CODES[country_name]
      return '' unless country_code
    end

    # Skip any remaining non-alpha-2 codes
    return '' unless country_code.match?(/\A[A-Za-z]{2}\z/)

    icon(country_code.downcase, library: 'flags', title: country_name)
  end

  private

  def country_to_code(country_name)
    mapping = Country.names_to_iso_a2

    return mapping[country_name] if mapping[country_name]

    mapping.each do |name, code|
      return code if country_name.downcase == name.downcase
      return code if country_name.downcase.include?(name.downcase) || name.downcase.include?(country_name.downcase)
    end

    nil
  end
end
