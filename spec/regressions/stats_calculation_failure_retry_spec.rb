# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Statistics calculation failures', type: :job do
  let(:user) { create(:user, settings: { 'locale' => 'fr' }) }
  let(:error) { ActiveRecord::StatementInvalid.new('synthetic database failure') }

  before do
    allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_raise(error)
    allow(ExceptionReporter).to receive(:call)
  end

  it 'propagates a service failure to its caller and reports it' do
    expect { Stats::CalculateMonth.new(user.id, 2026, 4).call }.to raise_error(error)
    expect(ExceptionReporter).to have_received(:call).with(error, anything)
    expect(user.notifications.count).to eq(1)
  end

  it 'propagates an internal failure from the job with one localized notification' do
    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(error)
    expect(user.notifications.count).to eq(1)
    expect(user.notifications.last.title).to eq('Échec de la mise à jour des statistiques')
  end

  it 'keeps one unread failure notification across retries of a persistent failure' do
    3.times { expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(error) }

    expect(user.notifications.count).to eq(1)
  end

  it 'keeps one unread failure notification across repeated service failures' do
    3.times { expect { Stats::CalculateMonth.new(user.id, 2026, 4).call }.to raise_error(error) }

    expect(user.notifications.count).to eq(1)
  end

  it 'notifies again once the earlier failure has been read' do
    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(error)
    user.notifications.update_all(read_at: Time.current)

    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(error)
    expect(user.notifications.count).to eq(2)
  end

  it 'keeps one unread notice per title across retries of a failing data recalculation' do
    create(:point, user: user, timestamp: Time.zone.local(2026, 4, 10).to_i)

    3.times { expect { Users::RecalculateDataJob.perform_now(user.id, year: 2026) }.to raise_error(error) }

    titles = user.notifications.pluck(:title)
    expect(titles).not_to be_empty
    expect(titles).to eq(titles.uniq)
  end

  it 'creates no failure notices for a silent data recalculation' do
    create(:point, user: user, timestamp: Time.zone.local(2026, 4, 10).to_i)

    expect { Users::RecalculateDataJob.perform_now(user.id, year: 2026, notify: false) }.to raise_error(error)
    expect(user.notifications.count).to eq(0)
  end

  it 'honors notification suppression while leaving the failure visible to retry' do
    expect do
      Stats::CalculatingJob.perform_now(user.id, 2026, 4, notify_on_failure: false)
    end.to raise_error(error)
    expect(user.notifications.count).to eq(0)
  end

  it 'allows a later delivery to recalculate successfully' do
    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(error)
    allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_call_original

    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.not_to raise_error
  end

  it 'still skips a deleted owner without reporting a calculation failure' do
    user.mark_as_deleted!
    expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.not_to raise_error
    expect(ExceptionReporter).not_to have_received(:call)
  end
end
