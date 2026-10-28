# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digest email configuration', type: :job do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    smtp_server = ENV['SMTP_SERVER']
    ENV.delete('SMTP_SERVER')
    example.run
  ensure
    ENV['SMTP_SERVER'] = smtp_server
  end

  let(:user) { create(:user, settings: {}) }

  [
    [Users::Digests::Monthly::EmailSendingJob, :monthly, :monthly_digest, 9],
    [Users::Digests::Yearly::EmailSendingJob, :yearly, :year_end_digest, nil],
    [Users::Digests::EmailSendingJob, :yearly, :year_end_digest, nil]
  ].each do |job_class, period_type, mailer_action, month|
    context job_class.name do
      let!(:digest) do
        user.digests.create!(year: 2025, month: month, period_type: period_type, distance: 12_345)
      end
      let(:arguments) { [user.id, digest.year, month].compact }

      [nil, '', '   '].each do |smtp_server|
        it "preserves the digest without enqueuing mail when SMTP_SERVER is #{smtp_server.inspect}" do
          ENV['SMTP_SERVER'] = smtp_server
          attributes = digest.attributes

          expect(DawarichSettings.email_configured?).to be(false)
          expect(user.safe_settings.public_send("#{period_type}_digest_emails_enabled?")).to be(true)

          aggregate_failures do
            expect do
              job_class.perform_now(*arguments)
            end.not_to have_enqueued_mail(Users::DigestsMailer, mailer_action)

            expect(digest.reload.attributes).to eq(attributes)
            expect(digest.sent_at).to be_nil
          end
        end
      end

      context 'when SMTP is configured' do
        before { ENV['SMTP_SERVER'] = 'smtp.example.test' }

        it 'enqueues mail and records sent_at only once' do
          freeze_time do
            expect do
              job_class.perform_now(*arguments)
            end.to have_enqueued_mail(Users::DigestsMailer, mailer_action).exactly(:once)

            expect(digest.reload.sent_at).to eq(Time.current)

            expect do
              job_class.perform_now(*arguments)
            end.not_to have_enqueued_mail(Users::DigestsMailer, mailer_action)
            expect(digest.reload.sent_at).to eq(Time.current)
          end
        end

        it 'respects the user email preference' do
          user.update!(settings: { "#{period_type}_digest_emails_enabled" => false })

          expect do
            job_class.perform_now(*arguments)
          end.not_to have_enqueued_mail(Users::DigestsMailer, mailer_action)
          expect(digest.reload.sent_at).to be_nil
        end
      end
    end
  end
end
