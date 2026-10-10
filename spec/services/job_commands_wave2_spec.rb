# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobCommands do
  it 'declares points exports at version 2 and the other wave-2 command types at version 1' do
    wave2_types = %w[
      exports.points
      mail.family_invitation
      mail.family_lapse
      mail.user.welcome
      mail.user.archival_approaching
      mail.user.oauth_account_link
      mail.user.account_destroy_confirmation
    ]

    versions = described_class::COMMANDS.slice(*wave2_types).transform_values { |command| command.fetch(:version) }
    expect(versions).to eq(wave2_types.index_with(1).merge('exports.points' => 2))
  end

  it "each legacy lambda enqueues today's job, arguments and locale" do
    link_url = 'https://example.test/?token=t'
    expected = {
      'exports.points' => [{ 'export_id' => 1, 'user_id' => 2 }, ExportJob, [1]],
      'mail.family_invitation' => [{ 'invitation_id' => 3, 'locale' => 'fr' }, Family::Invitations::SendingJob, [3]],
      'mail.family_lapse' => [
        { 'user_id' => 4, 'family_id' => 5, 'locale' => 'de', 'lapse_at' => 'none' },
        Families::LapseNotificationJob, [4, 5]
      ],
      'mail.user.welcome' => [{ 'user_id' => 6, 'locale' => 'es' }, Users::MailerSendingJob, [6, 'welcome']],
      'mail.user.archival_approaching' => [
        { 'user_id' => 7, 'locale' => 'pl', 'epoch' => 'e' }, Users::MailerSendingJob,
        [7, 'archival_approaching', { epoch: 'e' }]
      ],
      'mail.user.oauth_account_link' => [
        { 'user_id' => 8, 'locale' => 'ca', 'provider_label' => 'Google', 'link_url' => link_url },
        Users::MailerSendingJob, [8, 'oauth_account_link', { provider_label: 'Google', link_url: }]
      ],
      'mail.user.account_destroy_confirmation' => [
        { 'user_id' => 9, 'locale' => 'zh', 'link_url' => link_url }, Users::MailerSendingJob,
        [9, 'account_destroy_confirmation', { link_url: }]
      ]
    }

    expected.each do |type, (payload, job_class, arguments)|
      clear_enqueued_jobs
      I18n.with_locale(:en) { described_class::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, Time.current) }

      job = enqueued_jobs.sole
      expect(job[:job]).to eq(job_class)
      expect(ActiveJob::Arguments.deserialize(job[:args])).to eq(arguments)
      expect(job['locale']).to eq(payload.fetch('locale', 'en')), type
    end
  end

  it "a mail job produced inside a transaction keeps the payload's locale after commit" do
    link_url = 'https://example.test/?token=t'
    payloads = {
      'users.explore_features_mail' => { 'user_id' => 1, 'locale' => 'de' },
      'mail.family_invitation' => { 'invitation_id' => 3, 'locale' => 'fr' },
      'mail.family_lapse' => { 'user_id' => 4, 'family_id' => 5, 'locale' => 'de', 'lapse_at' => 'none' },
      'mail.user.welcome' => { 'user_id' => 6, 'locale' => 'es' },
      'mail.user.archival_approaching' => { 'user_id' => 7, 'locale' => 'pl', 'epoch' => 'e' },
      'mail.user.oauth_account_link' => {
        'user_id' => 8, 'locale' => 'ca', 'provider_label' => 'Google', 'link_url' => link_url
      },
      'mail.user.account_destroy_confirmation' => { 'user_id' => 9, 'locale' => 'zh', 'link_url' => link_url }
    }

    payloads.each do |type, payload|
      clear_enqueued_jobs
      ActiveRecord::Base.transaction do
        I18n.with_locale(:en) { described_class::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, Time.current) }
      end

      expect(enqueued_jobs.sole['locale']).to eq(payload.fetch('locale')), type
    end
  end
end
