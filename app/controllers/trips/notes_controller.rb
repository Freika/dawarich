# frozen_string_literal: true

module Trips
  class NotesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_trip
    before_action :set_note, only: %i[update destroy]

    def create
      date = note_params[:date].to_date
      @note = @trip.notes.for_date(date).first || @trip.notes.build(noted_at: date.to_datetime.noon)
      @note.user = current_user
      @note.body = note_params[:body]

      if @note.save
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "note-#{@trip.id}-#{@note.date}",
              partial: 'trips/notes/note',
              locals: { note: @note, trip: @trip }
            )
          end
          format.html { redirect_to @trip }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "note-#{@trip.id}-#{note_params[:date]}",
              partial: 'trips/notes/form',
              locals: { note: @note, trip: @trip }
            )
          end
          format.html { redirect_to @trip, alert: @note.errors.full_messages.join(', ') }
        end
      end
    end

    def update
      if @note.update(body: note_params[:body])
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "note-#{@trip.id}-#{@note.date}",
              partial: 'trips/notes/note',
              locals: { note: @note, trip: @trip }
            )
          end
          format.html { redirect_to @trip }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "note-#{@trip.id}-#{@note.date}",
              partial: 'trips/notes/form',
              locals: { note: @note, trip: @trip }
            )
          end
          format.html { redirect_to @trip, alert: @note.errors.full_messages.join(', ') }
        end
      end
    end

    def destroy
      date = @note.date
      @note.destroy!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "note-#{@trip.id}-#{date}",
            partial: 'trips/notes/empty',
            locals: { trip: @trip, date: date }
          )
        end
        format.html { redirect_to @trip }
      end
    end

    private

    def set_trip
      @trip = current_user.trips.find(params[:trip_id])
    end

    def set_note
      @note = @trip.notes.find(params[:id])
    end

    def note_params
      params.require(:note).permit(:date, :body)
    end
  end
end
