# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::LinkCountryNamesJob, type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:germany) { create(:country, name: 'Germany') }
  let!(:france) { create(:country, name: 'France', iso_a2: 'FR', iso_a3: 'FRA') }

  # update_columns, because the factory and its callbacks would link the row
  # and every example would pass without the job touching anything.
  def point_named(name, country_id:, owner: user)
    create(:point, user: owner).tap { |p| p.update_columns(country_name: name, country: nil, country_id: country_id) }
  end

  def run_backfill
    perform_enqueued_jobs { described_class.perform_later }
  end

  it 'links a localized name to the country its linked rows carry' do
    point_named('Deutschland', country_id: germany.id)
    unlinked = point_named('Deutschland', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to eq(germany.id)
  end

  it "uses other users' linked rows, so an account with no linked history is covered" do
    point_named('Deutschland', country_id: germany.id, owner: create(:user))
    unlinked = point_named('Deutschland', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to eq(germany.id)
  end

  it 'gathers the evidence across batches' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    point_named('Deutschland', country_id: germany.id)
    unlinked = point_named('Deutschland', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to eq(germany.id)
  end

  it 'leaves a name unlinked when its linked rows disagree' do
    point_named('Ambiguland', country_id: germany.id)
    point_named('Ambiguland', country_id: france.id)
    unlinked = point_named('Ambiguland', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to be_nil
  end

  it 'tolerates a stray mismatch once a name points almost entirely at one country' do
    stub_const("#{described_class}::MIN_SHARE", 0.75)
    3.times { point_named('Deutschland', country_id: germany.id) }
    point_named('Deutschland', country_id: france.id)
    unlinked = point_named('Deutschland', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to eq(germany.id)
  end

  it 'does not touch a name with no linked rows' do
    unlinked = point_named('Atlantis', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to be_nil
  end

  it 'never relinks a row that already has a country' do
    point_named('Deutschland', country_id: germany.id)
    linked = point_named('Deutschland', country_id: france.id)
    point_named('Deutschland', country_id: germany.id)
    stub_const("#{described_class}::MIN_SHARE", 0.6)

    run_backfill

    expect(linked.reload.country_id).to eq(france.id)
  end

  it 'leaves seed names to the name backfill, even when a linked row disagrees' do
    point_named('Germany', country_id: france.id)
    unlinked = point_named('Germany', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to be_nil
  end

  it 'never treats a blank name as evidence' do
    point_named('', country_id: germany.id)
    unlinked = point_named('', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to be_nil
  end

  it 'links a name that contains SQL placeholder or quote characters' do
    point_named("C?te d'Ivoire", country_id: germany.id)
    unlinked = point_named("C?te d'Ivoire", country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to eq(germany.id)
  end

  it 'links a row that only carries the legacy country column' do
    point_named('Deutschland', country_id: germany.id)
    legacy = create(:point, user:)
    legacy.update_columns(country_name: nil, country: 'Deutschland', country_id: nil)

    run_backfill

    expect(legacy.reload.country_id).to eq(germany.id)
  end

  it 'halves the batch and retries the same cursor when a batch is aborted' do
    point_named('Deutschland', country_id: germany.id)
    allow(Point).to receive(:where).and_call_original
    allow(Point).to receive(:where).with(id: anything).and_raise(ActiveRecord::QueryCanceled)
    start_id = Point.minimum(:id)

    expect { described_class.perform_now('tally', start_id, {}) }.to \
      have_enqueued_job(described_class).with('tally', start_id, {}, described_class::BATCH_SIZE / 2)
  end

  it 'hands the smallest batch to the retry machinery instead of shrinking forever' do
    point_named('Deutschland', country_id: germany.id)
    allow(Point).to receive(:where).and_call_original
    allow(Point).to receive(:where).with(id: anything).and_raise(ActiveRecord::QueryCanceled)
    start_id = Point.minimum(:id)

    expect { described_class.perform_now('tally', start_id, {}, described_class::MIN_BATCH_SIZE) }.to \
      have_enqueued_job(described_class).with('tally', start_id, {}, described_class::MIN_BATCH_SIZE)
  end

  it 'leaves geocoder aliases to the name backfill, even when a linked row disagrees' do
    point_named('United States', country_id: france.id)
    unlinked = point_named('United States', country_id: nil)

    run_backfill

    expect(unlinked.reload.country_id).to be_nil
  end

  it 'halves a link batch and retries the same cursor with the same links when it is aborted' do
    start_id = point_named('Deutschland', country_id: nil).id
    links = { 'Deutschland' => germany.id }
    allow(ActiveRecord::Base.connection).to receive(:update).and_raise(ActiveRecord::QueryCanceled)

    expect { described_class.perform_now('link', start_id, links) }.to \
      have_enqueued_job(described_class).with('link', start_id, links, described_class::BATCH_SIZE / 2)
  end

  it 'retries a tally batch with the tally from before it when reading the last id is aborted' do
    point_named('Deutschland', country_id: germany.id)
    start_id = Point.minimum(:id)
    allow(Point).to receive(:maximum).and_call_original
    allow(Point).to receive(:maximum).with(:id).and_raise(ActiveRecord::QueryCanceled)

    expect { described_class.perform_now('tally', start_id, {}) }.to \
      have_enqueued_job(described_class).with('tally', start_id, {}, described_class::BATCH_SIZE / 2)
  end

  it 'does nothing on an instance with no points' do
    expect { perform_enqueued_jobs { described_class.perform_later } }.not_to raise_error
  end
end
