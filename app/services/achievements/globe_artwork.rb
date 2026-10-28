# frozen_string_literal: true

module Achievements
  # Display-only geography. Eligibility remains in GeographicRegions/ObservedTime.
  class GlobeArtwork
    REGION_COLORS = { 'north' => '#46c4ed', 'south' => '#edb866',
                      'east' => '#52d2ac', 'west' => '#929cf1',
                      'ne' => '#46c4ed', 'nw' => '#a39cf2', 'se' => '#edb866', 'sw' => '#da8ac1',
                      'arctic' => '#73d4f3', 'antarctic' => '#f0c66c' }.freeze

    def self.call(card)
      new(card).call
    end

    def self.assets
      @assets ||= JSON.parse(Rails.root.join('lib/assets/achievement_collections/globes.json').read)
    end

    def initialize(card)
      @card = card
      @members = GeographicRegions::GROUPS.fetch(card.subject_key)
      @recorded = card.data.fetch('evidence', []).pluck('region') & @members
      view = %w[arctic antarctic].include?(card.subject_key) ? card.subject_key : 'equatorial'
      @view = self.class.assets.fetch('views').fetch(view)
    end

    def call
      raise 'Regenerate globe artwork for the current polar latitude' unless
        self.class.assets.fetch('polar_latitude') == GeographicRegions::POLAR_LATITUDE

      polar = @members.one?
      missing = if polar
                  cap = @view.fetch('regions').fetch(@members.first)
                  @recorded.any? ? "#{@view.fetch('sphere')} #{cap}" : @view.fetch('sphere')
                else
                  (@members - @recorded).map { |region| @view.fetch('regions').fetch(region) }.join(' ')
                end
      { path: @view.fetch('sphere'), viewbox: '-50 -50 100 100',
        unvisited_path: missing,
        colors: @recorded.map do |region|
          { path: @view.fetch('regions').fetch(region), color: REGION_COLORS.fetch(region) }
        end,
        details: details }
    end

    private

    def details
      boundary = case @card.subject_key
                 when 'north_south' then @view.fetch('equator')
                 when 'east_west' then @view.fetch('meridian')
                 when 'four_quarters' then @view.fetch('axes')
                 else @view.fetch('regions').fetch(@members.first)
                 end
      [
        { path: @view.fetch('land'), fill: '#0d1d28', stroke: '#d6e2d8', stroke_width: 0.22, opacity: 0.76 },
        { path: @view.fetch('graticule'), fill: 'none', stroke: '#c3d9e2', stroke_width: 0.18, opacity: 0.4 },
        { path: boundary, fill: 'none', stroke: '#fff3d5', stroke_width: 0.65, opacity: 0.92 },
        { path: @view.fetch('sphere'), fill: 'none', stroke: '#c8dfe4', stroke_width: 0.45, opacity: 0.8 }
      ]
    end
  end
end
