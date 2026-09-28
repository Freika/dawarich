# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JobCommands do
  payloads = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/wave2/payloads.json').read)
  link_url = payloads.dig('mail.user.oauth_account_link', 'link_url')

  describe 'rehome! of each wave-2 type re-enqueues its Sidekiq job from the payload and deletes the pending row' do
    {
      'exports.points' => [ExportJob, [11]],
      'mail.family_invitation' => [Family::Invitations::SendingJob, [12]],
      'mail.family_lapse' => [Families::LapseNotificationJob, [42, 13]],
      'mail.user.welcome' => [Users::MailerSendingJob, [42, 'welcome']],
      'mail.user.archival_approaching' => [
        Users::MailerSendingJob, [42, 'archival_approaching', { epoch: '2026-03-29T01:30:00Z' }]
      ],
      'mail.user.oauth_account_link' => [
        Users::MailerSendingJob, [42, 'oauth_account_link', { provider_label: 'Google', link_url: }]
      ],
      'mail.user.account_destroy_confirmation' => [
        Users::MailerSendingJob, [42, 'account_destroy_confirmation', { link_url: }]
      ]
    }.each do |type, (job_class, arguments)|
      it type do
        payload = payloads.fetch(type)
        job_owner!("command:#{type}", :oban)
        described_class.produce(type, payload, aggregate_id: 1, producer: 'spec')

        expect(described_class.rehome!(type, by: 'spec')).to eq({ moved: 1, left: 0 })

        job = enqueued_jobs.sole
        expect(job[:job]).to eq(job_class)
        expect(ActiveJob::Arguments.deserialize(job[:args])).to eq(arguments)
        expect(job['locale']).to eq(payload.fetch('locale', 'en'))
        expect(JobOutbox.count).to eq(0)
      end
    end
  end

  it 'no Rails wave-2 file references Oban or oban_jobs' do
    wave2_files = %w[
      app/controllers/auth/account_links_controller.rb
      app/jobs/export_job.rb
      app/jobs/families/lapse_notification_job.rb
      app/jobs/family/invitations/sending_job.rb
      app/jobs/lite/archival_warning_job.rb
      app/jobs/users/mailer_sending_job.rb
      app/models/export.rb
      app/models/notification.rb
      app/models/user.rb
      app/services/auth/find_or_create_oauth_user.rb
      app/services/families/invite.rb
      app/services/families/sync_members.rb
      app/services/job_commands.rb
      app/services/notifications/events_broadcaster.rb
      app/services/user_mail_commands.rb
      app/services/users/destroy.rb
      app/services/users/request_account_destroy.rb
      config/initializers/sidekiq.rb
    ]

    offenders = wave2_files.select { |path| Rails.root.join(path).read.match?(/\bOban\b|oban_jobs/) }

    expect(offenders).to be_empty
  end
end
