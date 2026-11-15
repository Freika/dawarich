# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Homes of a Place', type: :request do
  let(:user) { create(:user) }
  let(:place) { create(:place, user:) }

  before { sign_in user }

  it 'lists the Homes of the place on its edit page' do
    create(:home, user:, place:, started_on: Date.new(2018, 5, 1), ended_on: Date.new(2022, 3, 1))
    get edit_place_path(place)
    expect(response.body).to include('turbo-frame id="place_homes"', '2018-05-01', '2022-03-01')
  end

  it 'adds a Home with open dates' do
    expect { post place_homes_path(place), params: { home: { started_on: '', ended_on: '' } } }
      .to change(place.homes, :count).by(1)
    expect(place.homes.last).to have_attributes(user:, started_on: nil, ended_on: nil)
    expect(response).to redirect_to(edit_place_path(place))
    expect(response).to have_http_status(:see_other)
  end

  it 'adds a second period at the same place' do
    create(:home, user:, place:, ended_on: Date.new(2015, 1, 1))
    post place_homes_path(place), params: { home: { started_on: '2020-01-01' } }
    expect(place.homes.count).to eq(2)
  end

  it 'refuses an end before the start and keeps the form' do
    post place_homes_path(place), params: { home: { started_on: '2022-03-01', ended_on: '2022-02-01' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('turbo-frame id="place_homes"', '2022-03-01', '2022-02-01')
    expect(place.homes).to be_empty
  end

  it 'refuses to change a Home so that it ends before it starts' do
    home = create(:home, user:, place:, started_on: Date.new(2020, 1, 1))
    patch place_home_path(place, home), params: { home: { ended_on: '2019-01-01' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(home.reload.ended_on).to be_nil
  end

  it 'changes the dates of a Home' do
    home = create(:home, user:, place:)
    patch place_home_path(place, home), params: { home: { ended_on: '2026-06-30' } }
    expect(home.reload.ended_on).to eq(Date.new(2026, 6, 30))
  end

  it 'asks before removing a Home' do
    create(:home, user:, place:)
    get edit_place_path(place)
    form = Nokogiri::HTML(response.body).at_css("form[action^='#{place_homes_path(place)}/']:has(input[name='_method'][value='delete'])")
    expect(form['data-turbo-confirm']).to eq(I18n.t('trip_detection.homes.remove_confirm', raise: true))
  end

  it 'removes a Home' do
    home = create(:home, user:, place:)
    expect { delete place_home_path(place, home) }.to change(Home, :count).by(-1)
  end

  it "does not reach another user's place" do
    post place_homes_path(create(:place)), params: { home: { started_on: '' } }
    expect(response).to have_http_status(:not_found)
  end

  it 'makes a demo place the user\'s own when it becomes a Home' do
    demo_place = create(:place, user:, demo: true)
    post place_homes_path(demo_place), params: { home: { started_on: '' } }
    expect(demo_place.reload.demo).to be(false)
  end

  it 'leaves a demo place a demo when the Home is refused' do
    demo_place = create(:place, user:, demo: true)
    post place_homes_path(demo_place), params: { home: { started_on: '2022-03-01', ended_on: '2022-02-01' } }
    expect(demo_place.reload.demo).to be(true)
  end
end
