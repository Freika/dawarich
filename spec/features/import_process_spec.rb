# spec/features/import_process_spec.rb
require 'rails_helper'

RSpec.feature 'Import Process', type: :feature do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  scenario 'User imports a Google Phone Takeout file' do
    visit new_import_path

    choose 'Google Phone Takeout'
    attach_file 'import_files', Rails.root.join('spec/fixtures/files/google/phone-takeout.json')
    click_button 'Create Import'

    expect(page).to have_content('files are queued to be imported in background')
  end
end