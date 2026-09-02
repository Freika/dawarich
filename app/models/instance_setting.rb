# frozen_string_literal: true

# One stored Instance setting: a value that applies to the whole deployment
# rather than to a user. The environment still outranks anything stored here —
# InstanceSettings::Resolver decides that, not this model.
class InstanceSetting < ApplicationRecord
  encrypts :encrypted_value

  validates :key, presence: true, uniqueness: true
  validate :key_must_be_registered

  # Secrets live in the encrypted column and non-secrets in the plain one, but
  # callers should not have to know which. Assignment order is not guaranteed
  # (`new(value:, key:)` is as valid as `new(key:, value:)`), so the split is
  # re-applied whenever either half arrives — otherwise a secret assigned before
  # its key would land in the readable column.
  def value=(new_value)
    @pending_value = new_value
    @pending_value_assigned = true
    write_value_to_column
  end

  def key=(new_key)
    @definition = nil
    super
    write_value_to_column if @pending_value_assigned
  end

  def value
    return self[:value] unless definition&.secret?

    encrypted_value
  end

  def readable_value?
    encrypted_value
    true
  rescue ActiveRecord::Encryption::Errors::Decryption
    false
  end

  def definition
    return @definition if defined?(@definition) && @definition

    @definition = key.present? ? InstanceSettings::Registry.fetch(key) : nil
  rescue KeyError
    @definition = nil
  end

  private

  def write_value_to_column
    return if definition.nil?

    if definition.secret?
      self.encrypted_value = @pending_value&.to_s
      self[:value] = nil
    else
      self[:value] = @pending_value
    end
  end

  def key_must_be_registered
    return if key.blank?
    return if InstanceSettings::Registry.keys.include?(key.to_sym)

    errors.add(:key, 'is not a registered instance setting')
  end
end
