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
