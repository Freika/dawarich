# frozen_string_literal: true

# Deprecated browser compatibility endpoint. The Area record only preserves
# the old URL/ID contract; Place is the canonical entity being created or
# edited.
class AreasController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_area, only: %i[update]
  after_action :add_deprecation_header

  def create
    adapter.create(area_params)
    render turbo_stream: stream_flash(:success, I18n.t('controllers.areas.created'))
  rescue ActiveRecord::RecordInvalid => e
    render turbo_stream: stream_flash(:error, e.record.errors.full_messages.join(', '))
  end

  def update
    adapter.update(@area, area_params)
    render turbo_stream: stream_flash(:success, I18n.t('controllers.areas.updated'))
  rescue ActiveRecord::RecordInvalid => e
    render turbo_stream: stream_flash(:error, e.record.errors.full_messages.join(', '))
  end

  private

  def set_area
    @area = current_user.areas.find(params[:id])
  end

  def adapter
    @adapter ||= Places::LegacyAreaAdapter.new(user: current_user)
  end

  def add_deprecation_header
    response.set_header('Deprecation', 'true')
  end

  def area_params
    params.permit(:name, :latitude, :longitude, :radius)
  end
end
