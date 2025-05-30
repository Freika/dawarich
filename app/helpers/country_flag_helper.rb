# frozen_string_literal: true

module CountryFlagHelper
  def country_flag(country_name)
    country_code = country_to_code(country_name)
    return "" unless country_code

    # Convert country code to regional indicator symbols (flag emoji)
    country_code.upcase.each_char.map { |c| (c.ord + 127397).chr(Encoding::UTF_8) }.join
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
