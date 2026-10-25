# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:seed_changelog_prompt_user' do
  let(:email) { 'changelog-prompt@dawarich.app' }

  it 'creates a user who has not answered the changelog prompt yet' do
    Rake::Task['e2e:seed_changelog_prompt_user'].execute

    user = User.find_by!(email:)
    expect(user.valid_password?('safepassword')).to be(true)
    expect(user.changelog_consent).to be_nil
    expect(user.preferred_locale).to be_nil
  end

  it 'resets an earlier answer and saved language on every run' do
    create(:user, email:, changelog_consent: :declined, settings: { 'locale' => 'de' })

    Rake::Task['e2e:seed_changelog_prompt_user'].execute

    user = User.find_by!(email:)
    expect(user.changelog_consent).to be_nil
    expect(user.preferred_locale).to be_nil
    expect(User.where(email:).count).to eq(1)
  end
end
