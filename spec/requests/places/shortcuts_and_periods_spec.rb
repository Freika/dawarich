# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Place shortcuts and periods', type: :request do
  let(:user) { create(:user) }
  let(:place_params) { { name: 'Office', latitude: 52.52, longitude: 13.405, visit_radius: 100 } }

  before { sign_in user }

  def page = Nokogiri::HTML(response.body)

  describe 'the Add home and Add work buttons' do
    it 'are offered on the Places list' do
      get places_path
      expect(page.at_css("a[href='#{new_place_path(home: 1)}'][data-testid='add-home']")).to be_present
      expect(page.at_css("a[href='#{new_place_path(work: 1)}'][data-testid='add-work']")).to be_present
    end

    it 'open the Place form named Work with the Work tag ticked' do
      get new_place_path(work: 1)
      expect(page.at_css('input[name="place[name]"]')['value']).to eq(I18n.t('places.shortcuts.work_place_name'))
      expect(page.at_css('input[type="checkbox"][name="place[work]"]')['checked']).to be_present
      expect(page.at_css('h1').text).to eq(I18n.t('places.shortcuts.add_work'))
    end

    it 'do not offer the Work tag twice when the user already has it' do
      tag = create(:tag, user:, name: 'Work')
      get new_place_path(work: 1)
      expect(page.at_css("input[name='place[tag_ids][]'][value='#{tag.id}']")).to be_nil
    end

    it 'leave the plain new Place form without the Work shortcut' do
      get new_place_path
      expect(page.at_css('input[name="place[work]"]')).to be_nil
    end
  end

  describe 'creating a Place as work' do
    it 'creates the Work tag when the user has none and tags the Place' do
      expect { post places_path, params: { place: place_params.merge(work: '1') } }
        .to change(user.tags, :count).by(1)
      expect(user.places.last.tags.map(&:name)).to eq([I18n.t('places.shortcuts.work_place_name')])
      expect(user.tags.last.icon).to eq('💼')
    end

    it 'reuses the Work tag the user already has' do
      tag = create(:tag, user:, name: 'work')
      expect { post places_path, params: { place: place_params.merge(work: '1') } }
        .not_to change(Tag, :count)
      expect(user.places.last.tags).to eq([tag])
    end
  end

  describe 'the period of a Place' do
    it 'is asked for on the new Place form' do
      get new_place_path
      expect(page.at_css('input[type="date"][name="place[started_on]"]')).to be_present
      expect(page.at_css('input[type="date"][name="place[ended_on]"]')).to be_present
    end

    it 'is stored with a new Place' do
      post places_path, params: { place: place_params.merge(started_on: '2019-09-01', ended_on: '2022-06-30') }
      expect(user.places.last).to have_attributes(started_on: Date.new(2019, 9, 1), ended_on: Date.new(2022, 6, 30))
    end

    it 'becomes the Home period when the new Place is where the user lives' do
      post places_path, params: { place: place_params.merge(home: '1', started_on: '2021-03-01') }
      place = user.places.last
      expect(user.homes.last).to have_attributes(place:, started_on: Date.new(2021, 3, 1), ended_on: nil)
      expect(place).to have_attributes(started_on: nil, ended_on: nil)
    end

    it 'refuses an end before the start and creates nothing' do
      backwards = place_params.merge(home: '1', started_on: '2022-03-01', ended_on: '2022-02-01')
      expect { post places_path, params: { place: backwards } }.not_to change(Place, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t('trip_detection.homes.end_before_start')))
      expect(Home.count).to eq(0)
    end

    it 'is changed on the edit form' do
      place = create(:place, user:)
      patch place_path(place), params: { place: { ended_on: '2024-12-31' } }
      expect(place.reload.ended_on).to eq(Date.new(2024, 12, 31))
    end

    it 'is left to the Home periods on the edit form of a Home' do
      place = create(:place, user:)
      get edit_place_path(place)
      expect(page.at_css('input[name="place[started_on]"]')).to be_present

      create(:home, user:, place:)
      get edit_place_path(place)
      expect(page.at_css('input[name="place[started_on]"]')).to be_nil
    end
  end

  describe 'periods on the Places list' do
    def period_of(place) = page.at_css("tr[data-place-id='#{place.id}'] [data-testid='place-period']")&.text&.strip

    it 'shows an open and a closed period under the name and dims a past Place' do
      current = create(:place, user:, started_on: Date.new(2022, 1, 10))
      past = create(:place, user:, started_on: Date.new(2019, 9, 1), ended_on: Date.new(2022, 6, 30))
      undated = create(:place, user:)

      get places_path

      expect(period_of(current)).to eq(I18n.t('places.period.since', date: 'Jan 2022'))
      expect(period_of(past)).to eq(I18n.t('places.period.range', from: 'Sep 2019', to: 'Jun 2022'))
      expect(period_of(undated)).to be_nil
      expect(page.at_css("tr[data-place-id='#{past.id}']")['class']).to include('opacity-60')
      expect(page.at_css("tr[data-place-id='#{current.id}']")['class'].to_s).not_to include('opacity-60')
    end

    it 'shows the Home periods of a Home' do
      place = create(:place, user:)
      create(:home, user:, place:, started_on: Date.new(2015, 5, 1), ended_on: Date.new(2021, 3, 1))
      create(:home, user:, place:, started_on: Date.new(2024, 2, 1))

      get places_path

      expect(period_of(place)).to eq([I18n.t('places.period.range', from: 'May 2015', to: 'Mar 2021'),
                                      I18n.t('places.period.since', date: 'Feb 2024')].join(', '))
      expect(page.at_css("tr[data-place-id='#{place.id}']")['class'].to_s).not_to include('opacity-60')
    end
  end
end
