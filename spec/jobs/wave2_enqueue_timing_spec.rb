# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wave 2 Sidekiq enqueue timing' do
  def call_in_transaction(type, payload)
    ActiveRecord::Base.transaction do
      JobCommands::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, Time.current)
      enqueued_jobs.map { |job| job[:job] }
    end
  end

  it 'mail jobs enqueue inside the producer transaction, as they did before wave 2' do
    link_url = 'https://example.test/?token=t'
    commands = {
      'users.explore_features_mail' => [Users::MailerSendingJob, { 'user_id' => 1, 'locale' => 'de' }],
      'mail.family_invitation' => [Family::Invitations::SendingJob, { 'invitation_id' => 3, 'locale' => 'fr' }],
      'mail.user.welcome' => [Users::MailerSendingJob, { 'user_id' => 6, 'locale' => 'es' }],
      'mail.user.archival_approaching' => [
        Users::MailerSendingJob, { 'user_id' => 7, 'locale' => 'pl', 'epoch' => 'e' }
      ],
      'mail.user.oauth_account_link' => [
        Users::MailerSendingJob, { 'user_id' => 8, 'locale' => 'ca', 'provider_label' => 'Google', 'link_url' => link_url }
      ],
      'mail.user.account_destroy_confirmation' => [
        Users::MailerSendingJob, { 'user_id' => 9, 'locale' => 'zh', 'link_url' => link_url }
      ]
    }

    commands.each do |type, (job_class, payload)|
      clear_enqueued_jobs

      expect(call_in_transaction(type, payload)).to eq([job_class]), type
    end
  end

  it 'ExportJob and LapseNotificationJob enqueue after commit, as they did before wave 2' do
    commands = {
      'exports.points' => [ExportJob, { 'export_id' => 3, 'user_id' => 4 }],
      'mail.family_lapse' => [
        Families::LapseNotificationJob, { 'user_id' => 4, 'family_id' => 5, 'locale' => 'de', 'lapse_at' => 'none' }
      ]
    }

    commands.each do |type, (job_class, payload)|
      clear_enqueued_jobs

      expect(call_in_transaction(type, payload)).to eq([]), type
      expect(enqueued_jobs.map { |job| job[:job] }).to eq([job_class]), type
    end
  end
end
