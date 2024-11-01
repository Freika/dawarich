# frozen_string_literal: true

class Api::V1::Countries::BordersController < ApplicationController
  def index
    countries = Rails.cache.fetch('dawarich/countries_codes', expires_in: 1.day) do
      Oj.load(File.read(Rails.root.join('lib/assets/countries.json')))
    end

    render json: countries
  end
end
