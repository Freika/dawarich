# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Wave 2 enqueue-after-commit jobs' do
  it 'SendingJob, MailerSendingJob and ExportJob enqueue after commit' do
    commands = {
      'mail.family_invitation' => [Family::Invitations::SendingJob, { 'invitation_id' => 1, 'locale' => 'en' }],
      'mail.user.welcome' => [Users::MailerSendingJob, { 'user_id' => 2, 'locale' => 'en' }],
      'exports.points' => [ExportJob, { 'export_id' => 3, 'user_id' => 4 }]
    }

    commands.each do |type, (job_class, payload)|
      clear_enqueued_jobs
      ActiveRecord::Base.transaction do
        JobCommands::COMMANDS.fetch(type).fetch(:sidekiq).call(payload, Time.current)
        expect(enqueued_jobs).to be_empty
      end

      expect(enqueued_jobs.map { |job| job[:job] }).to eq([job_class])
    end
  end
end
