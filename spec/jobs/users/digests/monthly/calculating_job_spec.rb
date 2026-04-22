# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Monthly::CalculatingJob, type: :job do
  let(:user) { create(:user) }

  it 'runs Stats::CalculateMonth and Digests::CalculateMonth for the given period' do
    stat_double   = instance_double(Stats::CalculateMonth, call: true)
    digest_double = instance_double(Users::Digests::CalculateMonth, call: true)
    allow(Stats::CalculateMonth).to receive(:new).with(user.id, 2026, 3).and_return(stat_double)
    allow(Users::Digests::CalculateMonth).to receive(:new).with(user.id, 2026, 3).and_return(digest_double)

    described_class.new.perform(user.id, 2026, 3)

    expect(stat_double).to have_received(:call)
    expect(digest_double).to have_received(:call)
  end

  it 'chains Monthly::EmailSendingJob on success' do
    allow(Stats::CalculateMonth).to receive(:new).and_return(double(call: true))
    allow(Users::Digests::CalculateMonth).to receive(:new).and_return(double(call: true))

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.to have_enqueued_job(Users::Digests::Monthly::EmailSendingJob).with(user.id, 2026, 3)
  end

  it 'creates an error notification on failure' do
    allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError.new('boom'))

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.to change { user.reload.notifications.where(kind: :error).count }.by(1)
  end

  it 'does not enqueue email job on failure' do
    allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError.new('boom'))

    expect do
      described_class.new.perform(user.id, 2026, 3)
    end.not_to have_enqueued_job(Users::Digests::Monthly::EmailSendingJob)
  end
end
