# frozen_string_literal: true

class Users::ImportData::Tags
  def initialize(user, tags_data)
    @user = user
    @tags_data = tags_data
  end

  def call
    return 0 unless tags_data.is_a?(Array)

    Rails.logger.info "Importing #{tags_data.size} tags for user: #{user.email}"

    tags_created = 0

    tags_data.each do |tag_data|
      next unless tag_data.is_a?(Hash)
      next if tag_data['name'].blank?

      existing_tag = user.tags.find_by(name: tag_data['name'])

      if existing_tag
        Rails.logger.debug "Tag already exists: #{tag_data['name']}"
        next
      end

      begin
        user.tags.create!(tag_data)
        tags_created += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Skipping invalid tag: #{tag_data['name']}, error: #{e.message}"
        next
      end
    end

    Rails.logger.info "Tags import completed. Created: #{tags_created}"
    tags_created
  end

  private

  attr_reader :user, :tags_data
end
