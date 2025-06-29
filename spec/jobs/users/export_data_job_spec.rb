# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportDataJob, type: :job do
  let(:user) { create(:user) }
  let(:export_data) { Users::ExportData.new(user) }

  it 'exports the user data' do
    expect(Users::ExportData).to receive(:new).with(user).and_return(export_data)
    expect(export_data).to receive(:export)

    Users::ExportDataJob.perform_now(user.id)
  end
end
