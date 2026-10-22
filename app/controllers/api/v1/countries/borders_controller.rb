# frozen_string_literal: true

class Api::V1::Countries::BordersController < ApiController
  def index
    countries = Rails.cache.fetch('dawarich/countries_codes', expires_in: 1.day) do
      path = Rails.root.join('lib/assets/countries.geojson.gz')
      Zlib::GzipReader.open(path) { |gzip| Oj.load(gzip.read) }
    end

    render json: countries
  end
end
