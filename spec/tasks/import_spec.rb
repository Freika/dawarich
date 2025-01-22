# frozen_string_literal: true

require 'rails_helper'

describe 'import.rake' do
  let(:file_path) { Rails.root.join('spec/fixtures/files/google/records.json').to_s }
  let(:user) { create(:user) }

  it 'calls importing class' do
    expect(Tasks::Imports::GoogleRecords).to receive(:new).with(file_path, user.email).and_call_original.once

    Rake::Task['import:big_file'].invoke(file_path, user.email)
  end
end
