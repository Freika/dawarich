# frozen_string_literal: true

class Api::TrackSerializer
  EXCLUDED_ATTRIBUTES = %w[created_at updated_at user_id].freeze

  def initialize(track)
    @track = track
  end

  def call
    track.attributes.except(*EXCLUDED_ATTRIBUTES)
  end

  private

  attr_reader :track
end
