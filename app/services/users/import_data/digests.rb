# frozen_string_literal: true

class Users::ImportData::Digests
  def initialize(user, digests_data)
    @user = user
    @digests_data = digests_data
  end

  def call
    return 0 unless digests_data.is_a?(Array)

    Rails.logger.info "Importing #{digests_data.size} digests for user: #{user.email}"

    digests_created = 0

    digests_data.each do |digest_data|
      next unless digest_data.is_a?(Hash)

      existing_digest = find_existing_digest(digest_data)

      if existing_digest
        Rails.logger.debug "Digest already exists: #{digest_data['year']}/#{digest_data['month']}"
        next
      end

      begin
        create_digest_record(digest_data)
        digests_created += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed to create digest: #{e.message}"
        ExceptionReporter.call(e, 'Failed to create digest during import')
        next
      end
    end

    Rails.logger.info "Digests import completed. Created: #{digests_created}"
    digests_created
  end

  private

  attr_reader :user, :digests_data

  def find_existing_digest(digest_data)
    user.digests.find_by(
      year: digest_data['year'],
      month: digest_data['month'],
      period_type: digest_data['period_type']
    )
  end

  def create_digest_record(digest_data)
    attributes = digest_data.except('sharing_uuid')
    # Regenerate sharing_uuid for security - old share links shouldn't work for new user
    attributes['sharing_uuid'] = SecureRandom.uuid

    user.digests.create!(attributes)
  end
end
