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

  describe "a Place's own period" do
    let(:place) { create(:place, user:, started_on: Date.new(2019, 9, 1), ended_on: Date.new(2022, 6, 30)) }

    it 'gives way to an open-dated Home when the user says they live there now' do
      post place_homes_path(place, list: 1), params: { home: { started_on: '' } }
      expect(place.homes.last).to have_attributes(started_on: nil, ended_on: nil)
      expect(place.reload).to have_attributes(started_on: nil, ended_on: nil)
    end

    it 'gives way to the open Home of the onboarding, which stays a single Home' do
      2.times { Homes::CreateAtLocation.new(user:, latitude: place.lat, longitude: place.lon).call }
      expect(place.homes.pluck(:ended_on)).to eq([nil])
      expect(place.reload).to have_attributes(started_on: nil, ended_on: nil)
    end

    it 'gives way to the dates of a Home that has its own' do
      post place_homes_path(place), params: { home: { started_on: '2020-01-01' } }
      expect(place.homes.last).to have_attributes(started_on: Date.new(2020, 1, 1), ended_on: nil)
      expect(place.reload).to have_attributes(started_on: nil, ended_on: nil)
    end
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

  describe 'on the Places list' do
    def page = Nokogiri::HTML(response.body)

    before { place }

    it 'asks for a Home and offers "I live here" on each Place while there is none' do
      get places_path
      expect(response.body).to include(I18n.t('trip_detection.hints.no_home'))
      expect(page.at_css("[role='status'] a[href='#{new_place_path(home: 1)}']")).to be_present
      expect(page.at_css("form[action='#{place_homes_path(place, list: 1)}']")).to be_present
    end

    it 'names the Place on each "I live here" button for screen readers' do
      get places_path
      button = page.at_css("form[action='#{place_homes_path(place, list: 1)}'] button")
      expect(button['aria-label']).to eq(I18n.t('trip_detection.homes.live_here_at', place: place.name))
    end

    it 'marks the Home and stops asking once there is one' do
      create(:home, user:, place:)
      get places_path
      expect(page.at_css('[data-testid="place-home-badge"]')).to be_present
      expect(response.body).not_to include(I18n.t('trip_detection.hints.no_home'))
      expect(page.at_css("form[action^='#{place_homes_path(place)}']")).to be_nil
    end

    it 'does not ask when trip detection is off' do
      user.update!(settings: user.settings.merge('trip_detection_enabled' => false))
      get places_path
      expect(response.body).not_to include(I18n.t('trip_detection.hints.no_home'))
      expect(page.at_css("form[action^='#{place_homes_path(place)}']")).to be_nil
    end

    it 'makes the Place an open-dated Home in one click and returns to the list' do
      expect do
        post place_homes_path(place, list: 1), params: { home: { started_on: '' } },
                                               headers: { 'HTTP_REFERER' => places_url(q: 'flat') }
      end.to change(place.homes, :count).by(1)
      expect(place.homes.last).to have_attributes(started_on: nil, ended_on: nil)
      expect(response).to redirect_to(places_url(q: 'flat'))
      expect(flash[:notice]).to eq(I18n.t('trip_detection.onboarding.home_saved'))
    end

    it 'gives the new Home the dates of a dated Place instead of dropping them' do
      place.update!(started_on: Date.new(2019, 4, 1), ended_on: Date.new(2023, 9, 30))
      get places_path
      form = page.at_css("form[action='#{place_homes_path(place, list: 1)}']")
      fields = form.css('input[type=hidden]').to_h { |input| [input['name'], input['value'].to_s] }

      post form['action'], params: fields

      expect(place.homes.last).to have_attributes(started_on: Date.new(2019, 4, 1), ended_on: Date.new(2023, 9, 30))
    end
  end

  describe 'the "I live here" checkbox of a new Place' do
    let(:place_params) { { name: 'Flat', latitude: 52.52, longitude: 13.405, visit_radius: 100 } }

    def checkbox = Nokogiri::HTML(response.body).at_css('input[type="checkbox"][name="place[home]"]')

    it 'is offered unticked on the new Place form' do
      get new_place_path
      expect(checkbox).to be_present
      expect(checkbox['checked']).to be_nil
    end

    it 'is ticked, with the Place named Home, when the form is opened to add a Home' do
      get new_place_path(home: 1)
      expect(checkbox['checked']).to be_present
      expect(Nokogiri::HTML(response.body).at_css('input[name="place[name]"]')['value'])
        .to eq(I18n.t('trip_detection.home_place_name'))
    end

    it 'is left out of the edit form, which has the Home periods instead' do
      get edit_place_path(place)
      expect(checkbox).to be_nil
    end

    it 'makes the new Place an open-dated Home when ticked' do
      expect { post places_path, params: { place: place_params.merge(home: '1') } }
        .to change(user.homes, :count).by(1)
      expect(user.homes.last).to have_attributes(place: user.places.last, started_on: nil, ended_on: nil)
    end

    it 'adds no Home when left unticked' do
      expect { post places_path, params: { place: place_params.merge(home: '0') } }
        .to change(user.places, :count).by(1)
      expect(Home.count).to eq(0)
    end
  end
end
