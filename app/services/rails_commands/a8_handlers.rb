# frozen_string_literal: true

module RailsCommands
  module A8Handlers
    HANDLERS = {
      'route_videos.attachment_job' => {
        guard: 'Exact detached file identity and no remaining blob reference; missing blobs are harmless.',
        call: ->(payload) { A8Handlers.attachment_job(payload) }
      },
      'visits.web_redetect' => {
        guard: 'The existing full-history job independently rechecks cooldown under its user lock.',
        call: ->(payload) { A8Handlers.redetect(payload) }
      }
    }.freeze

    module_function

    def attachment_job(payload)
      return unless positive_ids?(payload, %w[user_id blob_id])
      return unless %w[purge_unattached purge_detached].include?(payload['action'])
      return unless payload['action'] == 'purge_unattached' || detached?(payload)

      blob = ActiveStorage::Blob.find_by(id: payload.fetch('blob_id'))
      return unless blob

      blob.with_lock do
        return if blob.attachments.exists?

        JobCommands.enqueue_after_commit(nil) { blob.purge_later }
      end
    end

    def detached?(payload)
      identity = payload['attachment']
      return false unless identity.is_a?(Hash) && positive_ids?(identity, %w[id record_id blob_id])
      return false unless identity['name'] == 'file' && identity['record_type'] == 'RouteVideo'
      return false unless identity['blob_id'] == payload['blob_id']
      return false if ActiveStorage::Attachment.exists?(identity.fetch('id'))

      video = RouteVideo.find_by(id: identity.fetch('record_id'))
      !video || video.user_id == payload.fetch('user_id')
    end

    def positive_ids?(payload, fields)
      fields.all? { |field| payload[field].is_a?(Integer) && payload[field].positive? }
    end

    def redetect(payload)
      return unless positive_ids?(payload, %w[user_id])

      user = User.find_by(id: payload.fetch('user_id'))
      return unless user

      I18n.with_locale(payload.fetch('locale', user.locale)) do
        Time.use_zone(payload.fetch('timezone', user.timezone)) do
          Visits::FullHistoryRedetectJob.perform_later(user.id)
        end
      end
    end
  end
end
