# frozen_string_literal: true

class DemoData::Importer
  DEMO_IMPORT_NAME = 'Demo Data (Berlin)'

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    return { status: :exists } if user.imports.exists?(demo: true)

    geojson_content = DemoData::GeojsonGenerator.new.call

    import = user.imports.build(
      name: DEMO_IMPORT_NAME,
      source: :geojson,
      demo: true
    )

    import.file.attach(
      io: StringIO.new(geojson_content),
      filename: 'demo_data.json',
      content_type: 'application/json'
    )

    import.save!

    { status: :created, import: import }
  end
end
