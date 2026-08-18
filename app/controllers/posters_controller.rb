# frozen_string_literal: true

class PostersController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    poster = current_user.posters.create!(
      name: poster_params[:name].presence || I18n.t('controllers.posters.untitled'),
      status: :created,
      settings: poster_params.except(:name).to_h
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.prepend('poster-gallery-list', partial: 'posters/poster', locals: { poster: poster }),
          stream_flash(:notice, I18n.t('controllers.posters.poster_generation_started_this_takes_about_a_minute'))
        ]
      end
      format.html do
        redirect_to map_v2_path,
                    notice: I18n.t('controllers.posters.poster_generation_started_this_takes_about_a_minute')
      end
    end
  rescue StandardError => e
    ExceptionReporter.call(e, 'Poster creation failed')

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: stream_flash(:error, I18n.t('controllers.posters.failed_to_start_poster_generation')),
               status: :unprocessable_content
      end
      format.html do
        redirect_to map_v2_path, alert: I18n.t('controllers.posters.failed_to_start_poster_generation'),
status: :unprocessable_content
      end
    end
  end

  def destroy
    poster = current_user.posters.find(params[:id])
    poster.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(ActionView::RecordIdentifier.dom_id(poster))
      end
      format.html { redirect_to map_v2_path, notice: I18n.t('controllers.posters.poster_deleted'), status: :see_other }
    end
  end

  private

  def poster_params
    params.require(:poster).permit(:name, :title, :lat, :lon, :distance, :theme, :start_at, :end_at, :source,
                                   :route_fill, :route_opacity, :route_width)
  end
end
