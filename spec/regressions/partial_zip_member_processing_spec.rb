# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'Accepted ZIP members after partial failure' do
  let(:user) { create(:user, :trial) }
  let(:parent) { create(:import, user: user, name: 'archive.zip') }
  let(:zip_path) { Rails.root.join('tmp', "partial_#{SecureRandom.hex(6)}.zip") }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    parent
    create_list(:import, 2, user: user)
    Zip::OutputStream.open(zip_path) do |zip|
      3.times do |i|
        zip.put_next_entry("ride_#{i}.csv")
        zip.write("latitude,longitude,timestamp\n52.5,13.4,1704067200\n")
      end
    end
    clear_enqueued_jobs
  end

  after { FileUtils.rm_f(zip_path) }

  it 'queues every saved member before reporting a later validation failure' do
    expect { Imports::ZipExtractor.new(parent, user.id, zip_path.to_s).call }
      .to raise_error(ActiveRecord::RecordInvalid)

    children = user.imports.where('name LIKE ?', '%(from archive.zip)')
    expect(children.count).to eq(2)
    expect(parent.reload).to be_failed
    children.each do |child|
      expect(Import::ProcessJob).to have_been_enqueued.with(child.id).exactly(:once)
    end
  end

  it 'does not requeue accepted members when extraction retries' do
    2.times do
      expect { Imports::ZipExtractor.new(parent, user.id, zip_path.to_s).call }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    children = user.imports.where('name LIKE ?', '%(from archive.zip)')
    expect(children.count).to eq(2)
    children.each do |child|
      expect(Import::ProcessJob).to have_been_enqueued.with(child.id).exactly(:once)
    end
  end
end
