# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map v2 date-navigation step is exactly one day', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { sign_in user }

  def nav_links_from(body)
    doc = Nokogiri::HTML(body)
    hrefs = doc.css('a.btn').map { |a| a['href'] }.compact.select do |href|
      href.start_with?('/map/v2?') && href.include?('start_at=') && href.include?('end_at=')
    end
    hrefs.map { |h| Rack::Utils.parse_nested_query(URI.parse(h).query) }
  end

  context 'with a manual whole-day window (00:00 → 23:59, no seconds)' do
    let(:start_at) { Time.zone.parse('2026-04-28 00:00:00') }
    let(:end_at)   { Time.zone.parse('2026-04-28 23:59:00') }

    it 'shifts the prev link back exactly 24 hours, preserving the window width' do
      get map_v2_path(start_at: start_at.iso8601, end_at: end_at.iso8601)

      params_sets = nav_links_from(response.body)
      prev_link = params_sets.find do |p|
        Time.zone.parse(p['start_at']) < start_at
      end

      expect(prev_link).not_to be_nil, 'expected a prev (chevron-left) link with shifted start_at'

      shifted_start = Time.zone.parse(prev_link['start_at'])
      shifted_end   = Time.zone.parse(prev_link['end_at'])

      expect(start_at - shifted_start).to eq(1.day),
                                          "prev link shifted start_at by #{start_at - shifted_start}s, expected 86400s"
      expect(end_at - shifted_end).to eq(1.day),
                                      "prev link shifted end_at by #{end_at - shifted_end}s, expected 86400s"
    end

    it 'shifts the next link forward exactly 24 hours, preserving the window width' do
      get map_v2_path(start_at: start_at.iso8601, end_at: end_at.iso8601)

      params_sets = nav_links_from(response.body)
      next_link = params_sets.find do |p|
        Time.zone.parse(p['end_at']) > end_at
      end

      expect(next_link).not_to be_nil, 'expected a next (chevron-right) link with shifted end_at'

      shifted_start = Time.zone.parse(next_link['start_at'])
      shifted_end   = Time.zone.parse(next_link['end_at'])

      expect(shifted_start - start_at).to eq(1.day),
                                          "next link shifted start_at by #{shifted_start - start_at}s, expected 86400s"
      expect(shifted_end - end_at).to eq(1.day),
                                      "next link shifted end_at by #{shifted_end - end_at}s, expected 86400s"
    end
  end

  context 'with the "Today" window (beginning_of_day → end_of_day)' do
    around do |example|
      travel_to(Time.zone.parse('2026-04-28 12:00:00')) { example.run }
    end

    let(:start_at) { Time.zone.now.beginning_of_day }
    let(:end_at)   { Time.zone.now.end_of_day }

    it 'shifts the prev link back exactly 24 hours' do
      get map_v2_path(start_at: start_at.iso8601, end_at: end_at.iso8601)

      params_sets = nav_links_from(response.body)
      prev_link = params_sets.find do |p|
        Time.zone.parse(p['start_at']) < start_at
      end

      expect(prev_link).not_to be_nil
      expect(start_at - Time.zone.parse(prev_link['start_at'])).to eq(1.day)
    end
  end
end
