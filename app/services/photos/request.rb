# frozen_string_literal: true

class Photos::Request
  attr_reader :user, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end

  def call
    photos = []

    photos << request_immich if user.immich_integration_configured?
    photos << request_photoprism if user.photoprism_integration_configured?

    photos
  end

  private

  def request_immich
    Immich::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call.reject { |asset| asset['type'].downcase == 'video' }
  end

  def request_photoprism
    Photoprism::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call.select { |asset| asset['Type'].downcase == 'image' }
  end
end
