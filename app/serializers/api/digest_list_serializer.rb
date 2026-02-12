# frozen_string_literal: true

class Api::DigestListSerializer
  def initialize(digests:, available_years:)
    @digests = digests
    @available_years = available_years
  end

  def call
    {
      digests: digests.map { |d| serialize_digest(d) },
      availableYears: available_years
    }
  end

  private

  attr_reader :digests, :available_years

  def serialize_digest(digest)
    {
      year: digest.year,
      distance: digest.distance,
      countriesCount: digest.countries_count,
      citiesCount: digest.cities_count,
      createdAt: digest.created_at.iso8601
    }
  end
end
