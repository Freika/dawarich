# frozen_string_literal: true

class ServiceSetting < ApplicationRecord
  belongs_to :user

  enum :service, { geocoding: 0 }, prefix: :service

  encrypts :credentials

  validates :provider, presence: true
  validates :provider, uniqueness: { scope: %i[user_id service] }

  before_validation :normalize_by_schema
  validate :validate_by_schema

  def activate!
    transaction do
      self.class.where(user_id: user_id, service: service).where.not(id: id).update_all(active: false)
      update!(active: true)
    end
  end

  def credentials_hash
    return {} if credentials.blank?

    JSON.parse(credentials)
  rescue JSON::ParserError, ActiveRecord::Encryption::Errors::Decryption
    {}
  end

  def api_key
    credentials_hash['api_key']
  end

  def api_key=(value)
    hash = credentials_hash
    if value.present?
      hash['api_key'] = value.to_s.strip
    else
      hash.delete('api_key')
    end
    self.credentials = hash.empty? ? nil : hash.to_json
  end

  def host
    config['host']
  end

  def use_https
    config.fetch('use_https', true)
  end

  def readable_credentials?
    credentials
    true
  rescue ActiveRecord::Encryption::Errors::Decryption
    false
  end

  def komoot?
    schema&.komoot? || false
  end

  def chibigeo?
    schema&.chibigeo? || false
  end

  def paid?
    schema&.paid? || false
  end

  private

  def schema
    @schema ||= ServiceSettings::GeocodingSchema.new(self) if service_geocoding?
  end

  def normalize_by_schema
    schema&.normalize
  end

  def validate_by_schema
    schema&.validate
  end
end
