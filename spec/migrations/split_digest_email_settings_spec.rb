# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260421000001_split_digest_email_settings.rb')

RSpec.describe SplitDigestEmailSettings, type: :migration do
  let(:migration) { described_class.new }

  describe '#up' do
    it 'maps digest_emails_enabled: true to both new keys true' do
      user = create(:user, settings: { 'digest_emails_enabled' => true })
      migration.up
      user.reload
      expect(user.settings['monthly_digest_emails_enabled']).to be true
      expect(user.settings['yearly_digest_emails_enabled']).to be true
      expect(user.settings).not_to have_key('digest_emails_enabled')
    end

    it 'maps digest_emails_enabled: false to both new keys false' do
      user = create(:user, settings: { 'digest_emails_enabled' => false })
      migration.up
      user.reload
      expect(user.settings['monthly_digest_emails_enabled']).to be false
      expect(user.settings['yearly_digest_emails_enabled']).to be false
      expect(user.settings).not_to have_key('digest_emails_enabled')
    end

    it 'defaults missing key to both new keys true' do
      user = create(:user, settings: {})
      migration.up
      user.reload
      expect(user.settings['monthly_digest_emails_enabled']).to be true
      expect(user.settings['yearly_digest_emails_enabled']).to be true
    end
  end

  describe '#down' do
    it 'reconstructs digest_emails_enabled from yearly value' do
      user = create(:user, settings: {
        'monthly_digest_emails_enabled' => true,
        'yearly_digest_emails_enabled' => false
      })
      migration.down
      user.reload
      expect(user.settings['digest_emails_enabled']).to be false
      expect(user.settings).not_to have_key('monthly_digest_emails_enabled')
      expect(user.settings).not_to have_key('yearly_digest_emails_enabled')
    end
  end
end
