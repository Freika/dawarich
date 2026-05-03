# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Digests transitional aliases', type: :job do
  # Helper that mimics the end-to-end path Sidekiq exercises when it pops a
  # JobWrapper payload off the queue: ActiveJob::Base.execute is called with
  # the raw job_data hash. ActiveJob's deserialize does
  # `job_data["job_class"].constantize.new` — so passing the legacy class
  # name (the transitional alias) verifies the autoload path resolves the
  # class without raising NameError, and that the resulting instance can
  # actually run the wrapped job's logic.
  def execute_legacy_payload(job_class_name, arguments, queue_name:)
    job_data = {
      'job_class'           => job_class_name,
      'job_id'              => SecureRandom.uuid,
      'provider_job_id'     => nil,
      'queue_name'          => queue_name,
      'priority'            => nil,
      'arguments'           => ActiveJob::Arguments.serialize(arguments),
      'executions'          => 0,
      'exception_executions' => {},
      'locale'              => I18n.locale.to_s,
      'timezone'            => Time.zone&.name,
      'enqueued_at'         => Time.now.utc.iso8601(9),
      'scheduled_at'        => nil
    }
    ActiveJob::Base.execute(job_data)
  end

  describe 'Users::Digests::EmailSendingJob' do
    it 'resolves to a real class via constantize' do
      expect { 'Users::Digests::EmailSendingJob'.constantize }.not_to raise_error
    end

    it 'is a subclass of the renamed Users::Digests::Yearly::EmailSendingJob' do
      expect('Users::Digests::EmailSendingJob'.constantize)
        .to be < Users::Digests::Yearly::EmailSendingJob
    end

    it 'enqueues to the same mailers queue as the renamed yearly job' do
      expect(Users::Digests::EmailSendingJob.new.queue_name)
        .to eq(Users::Digests::Yearly::EmailSendingJob.new.queue_name)
    end

    it 'can be enqueued via perform_later (unblocks legacy schedule entries)' do
      user = create(:user)
      expect do
        Users::Digests::EmailSendingJob.perform_later(user.id, 2025)
      end.to have_enqueued_job(Users::Digests::EmailSendingJob).with(user.id, 2025)
    end

    it 'deserializes a queued payload that names the legacy class and runs the wrapped logic' do
      user = create(:user, settings: { 'yearly_digest_emails_enabled' => true })
      digest = create(:users_digest, user: user, year: 2025, period_type: :yearly)

      expect do
        execute_legacy_payload(
          'Users::Digests::EmailSendingJob',
          [user.id, 2025],
          queue_name: 'mailers'
        )
      end.to have_enqueued_mail(Users::DigestsMailer, :year_end_digest)

      expect(digest.reload.sent_at).to be_present
    end
  end

  describe 'Users::Digests::CalculatingJob' do
    it 'resolves to a real class via constantize' do
      expect { 'Users::Digests::CalculatingJob'.constantize }.not_to raise_error
    end

    it 'is a subclass of the renamed Users::Digests::Yearly::CalculatingJob' do
      expect('Users::Digests::CalculatingJob'.constantize)
        .to be < Users::Digests::Yearly::CalculatingJob
    end

    it 'enqueues to the same digests queue as the renamed yearly job' do
      expect(Users::Digests::CalculatingJob.new.queue_name)
        .to eq(Users::Digests::Yearly::CalculatingJob.new.queue_name)
    end

    it 'can be enqueued via perform_later (unblocks legacy schedule entries)' do
      user = create(:user)
      expect do
        Users::Digests::CalculatingJob.perform_later(user.id, 2025)
      end.to have_enqueued_job(Users::Digests::CalculatingJob).with(user.id, 2025)
    end

    it 'deserializes a queued payload that names the legacy class and runs the wrapped logic' do
      user = create(:user)

      # The yearly calculating job recalculates monthly stats and computes
      # the year digest. We're not testing those services here — only that
      # the autoload path resolves the legacy alias and the wrapped #perform
      # is reached. Stub the leaf collaborators so the side effect we
      # assert on (the follow-up email-sending job being enqueued) is the
      # observable proof that perform actually ran.
      allow(Stats::CalculateMonth).to receive(:new).and_return(instance_double(Stats::CalculateMonth, call: true))
      allow(Users::Digests::CalculateYear).to receive(:new).and_return(
        instance_double(Users::Digests::CalculateYear, call: true)
      )

      expect do
        execute_legacy_payload(
          'Users::Digests::CalculatingJob',
          [user.id, 2025],
          queue_name: 'digests'
        )
      end.to have_enqueued_job(Users::Digests::Yearly::EmailSendingJob).with(user.id, 2025)
    end
  end
end
