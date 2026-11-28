# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExceptionReporter do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  it 'keeps the failure in the log on self-hosted installs' do
    allow(Rails.logger).to receive(:error)

    described_class.call(StandardError.new('boom'), 'Track generation failed')

    expect(Rails.logger).to have_received(:error).with('Track generation failed: boom')
  end

  it 'logs a plain message on self-hosted installs' do
    allow(Rails.logger).to receive(:error)

    described_class.call('Batch rejected', 'Some entries failed')

    expect(Rails.logger).to have_received(:error).with('Batch rejected: Some entries failed')
  end
end
