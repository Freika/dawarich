# frozen_string_literal: true

class SplitDigestEmailSettings < ActiveRecord::Migration[8.0]
  def up
    User.in_batches(of: 1000) do |batch|
      batch.each do |user|
        settings = user.settings || {}
        old_value = settings.fetch('digest_emails_enabled', true)
        settings['monthly_digest_emails_enabled'] = old_value
        settings['yearly_digest_emails_enabled']  = old_value
        settings.delete('digest_emails_enabled')
        user.update_column(:settings, settings)
      end
    end
  end

  def down
    User.in_batches(of: 1000) do |batch|
      batch.each do |user|
        settings = user.settings || {}
        settings['digest_emails_enabled'] =
          settings.fetch('yearly_digest_emails_enabled', true)
        settings.delete('monthly_digest_emails_enabled')
        settings.delete('yearly_digest_emails_enabled')
        user.update_column(:settings, settings)
      end
    end
  end
end
