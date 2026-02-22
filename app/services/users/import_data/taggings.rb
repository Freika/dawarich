# frozen_string_literal: true

class Users::ImportData::Taggings
  def initialize(user, taggings_data)
    @user = user
    @taggings_data = taggings_data
  end

  def call
    return 0 unless taggings_data.is_a?(Array)

    Rails.logger.info "Importing #{taggings_data.size} taggings for user: #{user.email}"

    taggings_created = 0

    taggings_data.each do |tagging_data|
      next unless tagging_data.is_a?(Hash)

      tag = find_tag(tagging_data)
      next unless tag

      taggable = find_taggable(tagging_data)
      next unless taggable

      existing = Tagging.find_by(tag: tag, taggable: taggable)
      if existing
        Rails.logger.debug "Tagging already exists: #{tag.name} -> #{taggable.try(:name)}"
        next
      end

      begin
        Tagging.create!(tag: tag, taggable: taggable)
        taggings_created += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Skipping invalid tagging: #{e.message}"
        next
      end
    end

    Rails.logger.info "Taggings import completed. Created: #{taggings_created}"
    taggings_created
  end

  private

  attr_reader :user, :taggings_data

  def find_tag(tagging_data)
    tag_name = tagging_data['tag_name']
    return nil if tag_name.blank?

    user.tags.find_by(name: tag_name)
  end

  def find_taggable(tagging_data)
    taggable_type = tagging_data['taggable_type']
    return nil if taggable_type.blank?

    case taggable_type
    when 'Place'
      find_place(tagging_data)
    else
      Rails.logger.warn "Unknown taggable type: #{taggable_type}"
      nil
    end
  end

  def find_place(tagging_data)
    name = tagging_data['taggable_name']
    latitude = tagging_data['taggable_latitude']&.to_f
    longitude = tagging_data['taggable_longitude']&.to_f

    return nil unless name.present? && latitude.present? && longitude.present?

    Place.find_by(name: name, latitude: latitude, longitude: longitude) ||
      Place.where(
        'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
        latitude - 0.0001, latitude + 0.0001,
        longitude - 0.0001, longitude + 0.0001
      ).first
  end
end
