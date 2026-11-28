# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, '#display_name' do
  it 'joins available nonblank name parts' do
    expect(build(:user, first_name: ' Ada ', last_name: ' Lovelace ').display_name).to eq('Ada Lovelace')
    expect(build(:user, first_name: nil, last_name: 'Hopper').display_name).to eq('Hopper')
    expect(build(:user, first_name: 'Grace', last_name: ' ').display_name).to eq('Grace')
  end

  it 'uses email when both names are missing or whitespace' do
    user = build(:user, first_name: ' ', last_name: nil)
    expect(user.display_name).to eq(user.email)
  end
end
