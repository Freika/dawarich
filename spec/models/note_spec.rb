# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Note, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:attachable).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:noted_at) }

    context 'uniqueness of date per attachable' do
      let(:user) { create(:user) }
      let(:trip) { create(:trip, user: user) }
      let!(:existing_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon)
      end

      it 'does not allow duplicate dates for the same attachable' do
        duplicate = build(:note, user: user, attachable: trip,
                                 noted_at: trip.started_at.to_date.to_datetime.noon)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:date]).to include('has already been taken')
      end

      it 'allows the same date for different attachables' do
        other_trip = create(:trip, user: user, started_at: trip.started_at, ended_at: trip.ended_at)
        note = build(:note, user: user, attachable: other_trip,
                            noted_at: trip.started_at.to_date.to_datetime.noon)
        expect(note).to be_valid
      end

      it 'allows multiple standalone notes on the same date' do
        note1 = create(:note, user: user, noted_at: Time.current)
        note2 = build(:note, user: user, noted_at: Time.current)
        expect(note1).to be_valid
        expect(note2).to be_valid
      end
    end

    context 'attachable belongs to user' do
      let(:user) { create(:user) }
      let(:other_user) { create(:user) }
      let(:trip) { create(:trip, user: user) }
      let(:other_trip) { create(:trip, user: other_user) }

      it 'is valid when attachable belongs to the same user' do
        note = build(:note, user: user, attachable: trip,
                            noted_at: trip.started_at.to_date.to_datetime.noon)
        expect(note).to be_valid
      end

      it 'is invalid when attachable belongs to a different user' do
        note = build(:note, user: user, attachable: other_trip,
                            noted_at: other_trip.started_at.to_date.to_datetime.noon)
        expect(note).not_to be_valid
        expect(note.errors[:attachable]).to include('must belong to the same user')
      end

      it 'is valid when attachable is blank (standalone note)' do
        note = build(:note, user: user, noted_at: Time.current)
        expect(note).to be_valid
      end
    end

    context 'date within trip range' do
      let(:user) { create(:user) }
      let(:trip) { create(:trip, user: user) }

      it 'is valid when date is within trip range' do
        note = build(:note, user: user, attachable: trip,
                            noted_at: trip.started_at.to_date.to_datetime.noon)
        expect(note).to be_valid
      end

      it 'is invalid when date is before trip start' do
        note = build(:note, user: user, attachable: trip,
                            noted_at: (trip.started_at.to_date - 1.day).to_datetime.noon)
        expect(note).not_to be_valid
        expect(note.errors[:date]).to include('must be within the trip date range')
      end

      it 'is invalid when date is after trip end' do
        note = build(:note, user: user, attachable: trip,
                            noted_at: (trip.ended_at.to_date + 1.day).to_datetime.noon)
        expect(note).not_to be_valid
        expect(note.errors[:date]).to include('must be within the trip date range')
      end
    end
  end

  describe '#date' do
    let(:user) { create(:user) }

    it 'derives date from noted_at' do
      note = build(:note, user: user, noted_at: DateTime.new(2025, 3, 15, 14, 30))
      expect(note.date).to eq(Date.new(2025, 3, 15))
    end
  end

  describe '#date=' do
    let(:user) { create(:user) }

    it 'sets noted_at to noon on the given date' do
      note = Note.new(user: user)
      note.date = '2025-03-15'
      expect(note.noted_at).to eq(Date.new(2025, 3, 15).to_datetime.noon)
    end
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }

    describe '.standalone' do
      let!(:standalone_note) { create(:note, user: user, noted_at: Time.current) }
      let!(:attached_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon)
      end

      it 'returns only notes without an attachable' do
        expect(described_class.standalone).to include(standalone_note)
        expect(described_class.standalone).not_to include(attached_note)
      end
    end

    describe '.attached' do
      let!(:standalone_note) { create(:note, user: user, noted_at: Time.current) }
      let!(:attached_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon)
      end

      it 'returns only notes with an attachable' do
        expect(described_class.attached).to include(attached_note)
        expect(described_class.attached).not_to include(standalone_note)
      end
    end

    describe '.for_trip_day' do
      let!(:trip_note) do
        create(:note, user: user, attachable: trip,
                      noted_at: trip.started_at.to_date.to_datetime.noon)
      end

      it 'returns notes for a specific trip and date' do
        result = described_class.for_trip_day(trip, trip.started_at.to_date)
        expect(result).to include(trip_note)
      end
    end
  end

  describe 'rich text' do
    let(:user) { create(:user) }
    let(:note) { create(:note, user: user, body: 'A wonderful day exploring the city', noted_at: Time.current) }

    it 'has rich text body' do
      expect(note.body).to be_an(ActionText::RichText)
      expect(note.body.to_plain_text).to eq('A wonderful day exploring the city')
    end
  end

  describe 'notable concern' do
    let(:user) { create(:user) }
    let(:trip) { create(:trip, user: user) }
    let!(:note) do
      create(:note, user: user, attachable: trip,
                    noted_at: trip.started_at.to_date.to_datetime.noon)
    end

    it 'nullifies notes when attachable is destroyed' do
      trip.destroy
      note.reload
      expect(note.attachable_id).to be_nil
      expect(note.attachable_type).to be_nil
    end
  end
end
