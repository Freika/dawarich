# frozen_string_literal: true

# Map Notes: standalone notes written at a point on the map. Trip day notes
# are written and edited on their trip.
class NotesController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :set_note, only: %i[edit update destroy]

  # Notes are read on the map, in the Timeline. Old links to the list land there.
  def index
    redirect_to map_v2_path(panel: 'timeline', month: 'latest')
  end

  def new
    @note = current_user.notes.build(
      latitude: params[:latitude], longitude: params[:longitude], noted_at: moment_param || Time.current
    )
  end

  def edit; end

  def create
    @note = current_user.notes.build(note_params.merge(params.require(:note).permit(:latitude, :longitude)))

    if located?(@note) && @note.save
      render_map_event('note:saved', t('notes.flash.saved'))
    else
      render :new, formats: :html, status: :unprocessable_content
    end
  end

  def update
    if @note.update(note_params)
      render_map_event('note:saved', t('notes.flash.saved'))
    else
      render :edit, formats: :html, status: :unprocessable_content
    end
  end

  def destroy
    @note.destroy!
    render_map_event('note:deleted', t('notes.flash.deleted'))
  end

  private

  def set_note
    @note = current_user.notes.standalone.find(params[:id])
  end

  # The point is set once, when the note is placed; editing never moves it.
  def note_params
    params.require(:note).permit(:body, :noted_at)
  end

  # The API accepts a note without a location; the map tool always places one.
  def located?(note)
    return true if note.latitude.present? && note.longitude.present?

    note.errors.add(:base, t('notes.flash.pick_a_point_on_the_map'))
    false
  end

  def moment_param
    Time.zone.parse(params[:noted_at].to_s)
  rescue ArgumentError
    nil
  end

  def render_map_event(name, message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update('map-note-event', partial: 'notes/map_event', locals: { name: name }),
          stream_flash(:notice, message)
        ]
      end
      format.html { redirect_to map_v2_path, notice: message }
    end
  end
end
