# frozen_string_literal: true

class VideoExportJob < ApplicationJob
  queue_as :video_exports

  def perform(video_export_id)
    video_export = VideoExport.find(video_export_id)
    video_export.update!(status: :processing)

    VideoExports::RequestRender.new(video_export:).call
  rescue StandardError => e
    video_export&.update!(status: :failed, error_message: e.message)
    ExceptionReporter.call(e)
  end
end
