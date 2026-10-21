# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'RailsCommands imports.progress' do
  include ActionCable::TestHelper
  let(:user) { create(:user) }
  let(:import) do
    Import.insert_all!([{ user_id: user.id, name: 'progress.gpx', source: 4, processed: 1234,
                         created_at: Time.current, updated_at: Time.current }])
    user.imports.order(:id).last
  end
  let(:payload) { { 'user_id' => user.id, 'import_id' => import.id, 'locale' => 'de' } }
  let(:stream) { Turbo::StreamsChannel.send(:stream_name_from, [user, :imports]) }

  def run(value = payload) = RailsCommands::Registry.handler('imports.progress').call(value)

  it 'renders current database progress to the existing user imports stream in the captured locale' do
    import
    messages = capture_broadcasts(stream) { run }
    expect(messages.length).to eq(1)
    html = messages.sole
    expect(html).to include('target="import_', 'data-points-total="1234"', 'progress.gpx')
    expect(html).to include(I18n.t('imports.table_row.delete_import', locale: :de))
  end

  it 'replays by rendering the current row rather than an old command count' do
    import
    messages = capture_broadcasts(stream) do
      run
      import.update_columns(processed: 4321)
      run
    end
    expect(messages.first).to include('data-points-total="1234"')
    expect(messages.last).to include('data-points-total="4321"')
  end

  it 'does not render a deleted import or an import owned by another user' do
    import
    messages = capture_broadcasts(stream) do
      run(payload.merge('user_id' => create(:user).id))
      run(payload.merge('import_id' => import.id + 1_000_000))
    end
    expect(messages).to be_empty
  end
end
