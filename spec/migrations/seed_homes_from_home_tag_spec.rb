# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261110090100_seed_homes_from_home_tag.rb')

RSpec.describe SeedHomesFromHomeTag do
  subject(:migrate) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  let(:user) { create(:user) }
  let(:place) { create(:place, user:) }

  def tag_place(place, name, owner: place.user)
    create(:tagging, taggable: place, tag: create(:tag, user: owner, name:))
  end

  it 'makes a Place tagged home an open-ended Home' do
    tag_place(place, 'Home')
    migrate
    expect(Home.where(place:)).to contain_exactly(have_attributes(user_id: user.id, started_on: nil, ended_on: nil))
  end

  it 'makes one Home of a Place tagged both "Home" and "home"' do
    tag_place(place, 'Home')
    tag_place(place, 'home')
    migrate
    expect(Home.where(place:).count).to eq(1)
  end

  it 'makes no second Home when it runs again' do
    tag_place(place, 'home')
    migrate
    migrate
    expect(Home.where(place:).count).to eq(1)
  end

  it "ignores another user's home tag on the Place" do
    tag_place(place, 'home', owner: create(:user))
    migrate
    expect(Home.where(place:)).to be_empty
  end
end
