# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import source files', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, status: :completed, source: :owntracks) }

  before do
    import.file.attach(io: StringIO.new('synthetic source'), filename: 'synthetic.json')
    sign_in user
  end

  it 'removes only the file and handles repeated requests' do
    point = create(:point, user: user, import: import)
    delete source_file_import_path(import)

    expect(response).to redirect_to(import_path(import))
    expect(import.reload.file).not_to be_attached
    expect(import.points.pluck(:id)).to eq([point.id])

    delete source_file_import_path(import)
    expect(response).to have_http_status(:see_other)
    expect(flash[:notice]).to eq(I18n.t('imports.source_file.already_deleted'))
  end

  it 'rejects another owner and signed-out requests' do
    sign_in create(:user)
    delete source_file_import_path(import)
    expect(response).to redirect_to(root_path)
    expect(import.reload.file).to be_attached

    sign_out :user
    delete source_file_import_path(import)
    expect(response).to redirect_to(new_user_session_path)
    expect(import.reload.file).to be_attached
  end

  it 'refuses processing imports even with a direct request' do
    import.update_columns(status: Import.statuses[:processing])
    delete source_file_import_path(import)

    expect(response).to redirect_to(import_path(import))
    expect(flash[:alert]).to eq(I18n.t('imports.source_file.unavailable'))
    expect(import.reload.file).to be_attached
  end

  it 'renders index, show and edit and handles downloads after removal without a server error' do
    delete source_file_import_path(import)

    get imports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(download_import_path(import))
    expect(response.body).to include('all its imported points')

    get import_path(import)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t('imports.source_file.missing'))
    expect(response.body).not_to include('extraction-dialog-')

    get edit_import_path(import)
    expect(response).to have_http_status(:ok)

    patch import_path(import), params: { import: { name: 'Renamed synthetic import' } }
    expect(response).to have_http_status(:see_other)
    expect(import.reload.name).to eq('Renamed synthetic import')

    get points_path(import_id: import.id)
    expect(response).to have_http_status(:ok)

    expect { get download_import_path(import) }.not_to have_enqueued_job(Imports::PrepareDownloadJob)
    expect(response).to redirect_to(import_path(import))
  end

  it 'can still delete the whole import and its points after source removal' do
    point = create(:point, user: user, import: import)
    delete source_file_import_path(import)
    delete import_path(import)

    expect(response).to have_http_status(:see_other)
    Imports::DestroyJob.perform_now(import.id)
    expect(Import.exists?(import.id)).to be false
    expect(Point.exists?(point.id)).to be false
  end

  it 'prevents extraction after removal, but still allows removal of previously extracted data' do
    import.update_columns(source: Import.sources[:google_phone_takeout],
                          additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed])
    delete source_file_import_path(import)

    expect { post import_extraction_path(import) }.not_to have_enqueued_job(EnhancedImport::ExtractJob)
    expect(response).to redirect_to(root_path)

    expect { delete import_extraction_path(import) }.to have_enqueued_job(EnhancedImport::DestroyJob)
  end

  it 'does not allow removal between queuing and starting download preparation' do
    archive = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry('synthetic.json')
      zip.write('{}')
    end
    import.file.attach(io: StringIO.new(archive.string), filename: 'synthetic.json.zip')

    get download_import_path(import)
    expect(response).to have_http_status(:accepted)
    expect(import.reload.download_preparation_pending?).to be true

    delete source_file_import_path(import)
    expect(import.reload.file).to be_attached
    expect(flash[:alert]).to eq(I18n.t('imports.source_file.unavailable'))

    travel 2.minutes do
      expect { get download_import_path(import) }
        .to have_enqueued_job(Imports::PrepareDownloadJob).with(import.id, import.file.blob_id)
    end

    Imports::PrepareDownloadJob.perform_now(import.id, import.file.blob_id)
    expect(import.reload.download_preparation_pending?).to be false
    delete source_file_import_path(import)
    expect(import.reload.file).not_to be_attached
    expect(import.prepared_download).not_to be_attached
  end

  %i[en de es fr ca pl zh].each do |locale|
    it "translates source deletion and whole-import confirmations in #{locale}" do
      user.update!(settings: user.settings.merge('locale' => locale.to_s))
      get import_path(import)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      source_form = document.at_css("form[action='#{source_file_import_path(import)}']")
      expect(source_form['data-turbo-confirm']).to eq(I18n.t('imports.source_file.confirmation', locale: locale))
      expect(source_form.text).to include(I18n.t('imports.source_file.delete', locale: locale))

      get imports_path
      document = Nokogiri::HTML(response.body)
      delete_link = document.at_css("a[href='#{import_path(import)}'][data-turbo-method='delete']")
      expect(delete_link['data-turbo-confirm']).to eq(I18n.t('imports.source_file.delete_import_confirmation',
                                                             locale: locale))
      expect(response.body).not_to include('translation_missing')
    end
  end
end
