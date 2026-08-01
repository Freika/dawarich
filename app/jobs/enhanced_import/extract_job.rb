# frozen_string_literal: true

module EnhancedImport
  class ExtractJob < ApplicationJob
    queue_as :extractions

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return if import.nil?

      return unless EnhancedImport::Translator.supported?(import.source)

      run(import)
    rescue ActiveRecord::RecordNotFound => e
      ExceptionReporter.call(e)
    end

    private

    # Import completion schedules track generation too, and both claim the same
    # untracked points. The generator already serialises on this lock.
    def run(import)
      mark_running!(import)

      counts = Tracks::PerUserLock.with_user_lock(import.user_id) do
        process_stream(import)
      end

      mark_completed!(import, counts)
    rescue Tracks::PerUserLock::AcquisitionTimeout
      # Sibling imports from one archive all finish together; wait our turn
      # rather than surfacing a red card the user can do nothing about.
      requeue(import)
    rescue StandardError => e
      mark_failed!(import, e)
      ExceptionReporter.call(e)
      raise
    end

    def requeue(import)
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:pending],
        additional_data_extraction: import.additional_data_extraction.merge('started_at' => Time.current.iso8601)
      )
      self.class.set(wait: 1.minute).perform_later(import.id)
    end

    def process_stream(import)
      counts = Hash.new(0)
      user = import.user
      place_writer = Writers::PlaceWriter.new(user, import)
      visit_writer = Writers::VisitWriter.new(user, import)
      track_writer = Writers::TrackWriter.new(user, import)
      segment_writer = Writers::SegmentWriter.new

      EnhancedImport::Translator.new(import).translate do |item|
        case item
        when Extracted::Place
          place, = place_writer.upsert(item)
          counts[:places] += 1 if place
        when Extracted::Visit
          place, = place_writer.upsert(item.place)
          counts[:places] += 1 if place
          visit, = visit_writer.upsert(item, place)
          counts[:visits] += 1 if visit
        when Extracted::Track
          source_segments_take_over = trust_source?(import) && item.segments.any?
          track, = track_writer.upsert(
            item,
            skip_segment_detection: source_segments_take_over
          )
          counts[:tracks] += 1 if track
          if track && source_segments_take_over
            item.segments.each do |segment|
              written_segment, = segment_writer.upsert(track, segment)
              counts[:segments] += 1 if written_segment
            end
            track.update_dominant_mode!
          end
        end
      end

      counts
    end

    def trust_source?(import)
      import.additional_data_extraction.fetch('options', {}).fetch('trust_source', true)
    end

    def broadcast_card(import)
      Turbo::StreamsChannel.broadcast_replace_to(
        "import_#{import.id}_extraction",
        target: "import-#{import.id}-extraction",
        partial: 'imports/extraction_card',
        locals: { import: import.reload }
      )
    rescue StandardError => e
      Rails.logger.warn("[EnhancedImport::ExtractJob] card broadcast failed import_id=#{import.id}: #{e.message}")
    end

    def mark_running!(import)
      payload = import.additional_data_extraction.merge(
        'started_at' => Time.current.iso8601,
        'completed_at' => nil,
        'error_message' => nil
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: payload
      )
      broadcast_card(import)
    end

    def mark_completed!(import, counts)
      payload = import.additional_data_extraction.merge(
        'completed_at' => Time.current.iso8601,
        'counts' => counts.transform_keys(&:to_s),
        'error_message' => nil
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed],
        additional_data_extraction: payload
      )
      broadcast_card(import)
    end

    def mark_failed!(import, error)
      payload = import.additional_data_extraction.merge(
        'completed_at' => Time.current.iso8601,
        'error_message' => error.message
      )
      import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:failed],
        additional_data_extraction: payload
      )
      broadcast_card(import)
    end
  end
end
