# frozen_string_literal: true

class Api::V1::NotesController < ApiController
  before_action :set_note, only: %i[show update destroy]

  def index
    notes = current_api_user.notes

    notes = notes.where(attachable_type: params[:attachable_type]) if params[:attachable_type].present?
    notes = notes.where(attachable_id: params[:attachable_id]) if params[:attachable_id].present?
    notes = notes.standalone if params[:standalone] == 'true'

    render json: notes.ordered.map { Api::NoteSerializer.new(_1).call }, status: :ok
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

    render json: { message: 'Note was successfully deleted' }, status: :ok
  end

  private

  def set_note
    @note = current_api_user.notes.find(params[:id])
  end

  def note_params
    params.require(:note).permit(:title, :body, :latitude, :longitude, :attachable_type,
                                 :attachable_id, :noted_at)
  end
end
