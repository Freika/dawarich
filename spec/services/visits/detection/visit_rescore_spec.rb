# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::VisitRescore do
  let(:user) { create(:user) }
  let(:policy) { Visits::Detection::Policy.for(user) }
  let(:started_at) { Time.zone.parse('2026-01-05 09:00:00 UTC') }
  let(:visit) do
    create(:visit, user: user, status: :confirmed, confidence: nil,
                   started_at: started_at, ended_at: started_at + 1.hour, duration: 60)
  end

  before do
    allow(DawarichSettings).to receive_messages(reverse_geocoding_enabled?: false, store_geodata?: false)
  end

  def add_point(accuracy: 10, lonlat: 'POINT(-137.456 -48.123)')
    create(:point, user: user, visit: visit, lonlat: lonlat, accuracy: accuracy)
  end

  %i[area place unattributed].each do |attribution|
    context "with #{attribution} attribution" do
      before do
        next if attribution == :unattributed

        location = create(attribution, user: user, latitude: -48.123, longitude: -137.456)
        visit.update!(attribution => location)
      end

      %i[queried preloaded].each do |source|
        context "with #{source} points" do
          def rescore(source)
            if source == :preloaded
              points = Point.where(visit_id: visit.id).select(:id, :accuracy, :lonlat).to_a
              described_class.call(visit, policy, points: points)
            else
              described_class.call(visit, policy)
            end
          end

          it 'scores mixed points exactly like coordinate-bearing evidence alone' do
            3.times do |i|
              add_point(lonlat: "POINT(#{-137.456 + i * 0.0003} #{-48.123 + i * 0.0003})")
            end
            rescore(source)
            expected = visit.reload.attributes.slice('confidence', 'confidence_breakdown')
            expect(expected['confidence']).to be_present
            invalid = add_point(accuracy: 1000)
            invalid.update_columns(lonlat: nil)
            visit.update_columns(confidence: nil, confidence_breakdown: {})

            rescore(source)

            expect(visit.reload.attributes.slice('confidence', 'confidence_breakdown')).to eq(expected)
            expect(visit.status).to eq('confirmed')
            expect(visit.detection_version).to be_nil
          end

          it 'leaves a visit with only coordinate-less points unscored and confirmed' do
            add_point.update_columns(lonlat: nil)

            rescore(source)

            expect(visit.reload).to have_attributes(confidence: nil, confidence_breakdown: {}, status: 'confirmed')
          end

          it 'preserves an existing score when no coordinate-bearing evidence remains' do
            add_point.update_columns(lonlat: nil)
            visit.update_columns(confidence: 85, confidence_breakdown: { dwell: 1.0 })

            rescore(source)

            expect(visit.reload).to have_attributes(confidence: 85, confidence_breakdown: { 'dwell' => 1.0 },
                                                    status: 'confirmed')
          end

          it 'leaves an empty visit unscored and confirmed' do
            rescore(source)

            expect(visit.reload).to have_attributes(confidence: nil, confidence_breakdown: {}, status: 'confirmed')
          end
        end
      end
    end
  end

  it 'does not load visit points when an empty preloaded set is supplied' do
    add_point
    expect(Point).not_to receive(:where)

    described_class.call(visit, policy, points: [])

    expect(visit.reload.confidence).to be_nil
  end
end
