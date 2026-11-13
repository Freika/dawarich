# frozen_string_literal: true

class Api::V1::NotesController < ApiController
  before_action :set_note, only: %i[show update destroy]

  BOUNDS_PARAMS = %i[min_lon min_lat max_lon max_lat].freeze
  MAX_PER_PAGE = 500

  # Notes are the user's own writing and are not limited by the plan's data
  # window (ADR-0029), so this read is deliberately not plan-scoped.
  def index
    notes = map_read_masker.mask_notes(filtered_notes).ordered.includes(:user)
    notes = paginate(notes) if params[:page].present?

    render json: notes.map { Api::NoteSerializer.new(_1).call }, status: :ok
  end

  def show
    render json: Api::NoteSerializer.new(@note).call, status: :ok
  end

  def create
    @note = current_api_user.notes.build(note_params)

    if @note.save
      render json: Api::NoteSerializer.new(@note).call, status: :created
    else
      render json: { errors: @note.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @note.update(note_params)
      render json: Api::NoteSerializer.new(@note).call, status: :ok
    else
      render json: { errors: @note.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @note.destroy!

    render json: { message: I18n.t('controllers.api.v1.notes.note_was_successfully_deleted') }, status: :ok
  end

  private

  def filtered_notes
    notes = current_api_user.notes
    notes = notes.where(attachable_type: params[:attachable_type]) if params[:attachable_type].present?
    notes = notes.where(attachable_id: params[:attachable_id]) if params[:attachable_id].present?
    notes = notes.standalone if params[:standalone] == 'true'
    notes = notes.where(noted_at: (params[:start_at].presence)..) if params[:start_at].present?
    notes = notes.where(noted_at: ..(params[:end_at].presence)) if params[:end_at].present?
    notes = notes.within_bounds(*params.values_at(*BOUNDS_PARAMS)) if BOUNDS_PARAMS.all? { params[_1].present? }
    notes
  end

  # Optional, as for visits: without a page the whole list is returned.
  def paginate(notes)
    per_page = params[:per_page].to_i
    per_page = 100 unless per_page.positive?
    notes = notes.page(params[:page]).per([per_page, MAX_PER_PAGE].min)

    response.set_header('X-Current-Page', notes.current_page.to_s)
    response.set_header('X-Total-Pages', notes.total_pages.to_s)
    notes
  end

  def set_note
    @note = current_api_user.notes.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:title, :body, :latitude, :longitude, :attachable_type,
                                 :attachable_id, :noted_at)
  end
end
