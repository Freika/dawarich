# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::ImportSucceeded do
  let(:user) { create(:user) }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  def import_with_points(status: :completed, **attrs)
    create(:import, user:, status:, **attrs).tap { |import| create(:point, user:, import:) }
  end

  context 'with a single-file import' do
    it 'records one event and enqueues its delivery when the import completed with points' do
      import = import_with_points

      expect { described_class.new(import).call }.to have_enqueued_job(Analytics::DeliverEventJob)

      event = AnalyticsEvent.sole
      expect(event).to be_event_import_succeeded
      expect(event.user).to eq(user)
      expect(event.properties).to eq('result' => 'complete', 'files' => 1)
    end

    it 'records nothing when the import saved no points' do
      import = create(:import, user:, status: :completed)

      expect { described_class.new(import).call }.not_to(change(AnalyticsEvent, :count))
    end

    it 'records nothing when the import failed, even with points saved' do
      import = import_with_points(status: :failed)

      expect { described_class.new(import).call }.not_to(change(AnalyticsEvent, :count))
    end

    it 'records nothing for the demo import' do
      import = import_with_points(demo: true)

      expect { described_class.new(import).call }.not_to(change(AnalyticsEvent, :count))
    end

    it 'records nothing on self-hosted instances' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      import = import_with_points

      expect { described_class.new(import).call }.not_to(change(AnalyticsEvent, :count))
    end

    it 'records the event once when the job runs again' do
      import = import_with_points

      2.times { described_class.new(import).call }

      expect(AnalyticsEvent.count).to eq(1)
    end
  end

  context 'with imports extracted from one ZIP' do
    let(:archive_import_id) { 9_999 }

    it 'waits until every file of the archive has finished' do
      finished = import_with_points(archive_import_id:)
      create(:import, user:, status: :processing, archive_import_id:)

      expect { described_class.new(finished).call }.not_to(change(AnalyticsEvent, :count))
    end

    it 'records one complete result for the archive when all files completed' do
      first = import_with_points(archive_import_id:)
      second = create(:import, user:, status: :completed, archive_import_id:)

      described_class.new(first).call
      described_class.new(second).call

      expect(AnalyticsEvent.sole.properties).to eq('result' => 'complete', 'files' => 2)
    end

    it 'records a partial result when some files failed' do
      import_with_points(archive_import_id:)
      failed = create(:import, user:, status: :failed, archive_import_id:)

      described_class.new(failed).call

      expect(AnalyticsEvent.sole.properties).to eq('result' => 'partial', 'files' => 2)
    end
  end

  it 'never raises, so a recording failure cannot fail the import' do
    import = import_with_points
    allow(AnalyticsEvent).to receive(:record).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { described_class.new(import).call }.not_to raise_error
  end
end
