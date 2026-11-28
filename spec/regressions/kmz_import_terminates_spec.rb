# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'KMZ imports terminate without importing their source archive' do
  let(:user) { create(:user) }
  let(:kml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
          <Placemark><name>Test point</name><Point><coordinates>13.4,52.5,0</coordinates></Point></Placemark>
        </Document>
      </kml>
    XML
  end

  def kmz_content
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('doc.kml')
      zip.write(kml)
      zip.put_next_entry('images/icon.png')
      zip.write("\x89PNG\r\n\x1A\n".b)
    end.string
  end

  def attached_import(filename, content)
    import = user.imports.build(name: filename, skip_background_processing: true)
    import.file.attach(io: StringIO.new(content), filename: filename)
    import.save!
    import
  end

  def processing_jobs
    enqueued_jobs.select { |job| job[:job] == Import::ProcessJob }
  end

  it 'queues only the extracted KML, then finishes with a zero-points warning' do
    import = attached_import('journey.kmz', kmz_content)
    clear_enqueued_jobs

    import.process!

    expect(user.imports.reload.map { |child| child.file.filename.to_s }).to eq(['doc.kml'])
    child = user.imports.reload.sole
    expect(processing_jobs.pluck(:args)).to eq([[child.id]])

    clear_enqueued_jobs
    Import::ProcessJob.perform_now(child.id)

    expect(child.reload).to be_completed
    expect(child.points.count).to eq(0)
    expect(processing_jobs).to be_empty
    expect(user.notifications.where(kind: :warning).last.content).to include('timestamps')
  end

  it 'does not recreate the KMZ through successive processing rounds' do
    import = attached_import('journey.kmz', kmz_content)
    import.process!

    3.times do
      user.imports.where(status: :created).to_a.each do |child|
        Import::ProcessJob.perform_now(child.id)
      end
    end

    expect(user.imports.reload.map { |child| child.file.filename.to_s }).to eq(['doc.kml'])
    expect(user.imports.reload.sole).to be_completed
  end

  it 'imports a legitimate nested KMZ with the same name as the staging archive' do
    content = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('nested/_source.kmz')
      zip.write(kmz_content)
      zip.put_next_entry('readme.txt')
      zip.write('Nested journey')
    end.string
    import = attached_import('collection.kmz', content)
    import.process!

    expect(user.imports.reload.map { |child| child.file.filename.to_s }).to eq(['_source.kmz'])
    nested_import = user.imports.reload.sole
    Import::ProcessJob.perform_now(nested_import.id)

    expect(user.imports.reload.map { |child| child.file.filename.to_s }).to eq(['doc.kml'])
    Import::ProcessJob.perform_now(user.imports.reload.sole.id)
    expect(user.imports.reload.sole).to be_completed
  end
end
