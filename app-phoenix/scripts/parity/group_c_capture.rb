# frozen_string_literal: true

module GroupCCapture
  def self.included(base)
    base.before do
      config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                  'action_dispatch.show_detailed_exceptions' => false)
      allow(Rails.application).to receive(:env_config).and_return(config)
    end
  end

  def group_c_rows(tables)
    tables.to_h do |table|
      rows = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, rows.map { JSON.parse(_1) }]
    end
  end

  def group_c_write(kind, fixture)
    path = Rails.root.join("app-phoenix/test/golden_captures/#{kind}.json")
    if path.exist?
      previous = JSON.parse(path.read)
      names = fixture.fetch('cases').map { _1.fetch('name') }
      fixture['cases'] = (previous.fetch('cases').reject { names.include?(_1.fetch('name')) } +
                          fixture.fetch('cases')).sort_by { _1.fetch('name') }
      fixture['setups'] = previous.fetch('setups', {}).merge(fixture['setups']) if fixture.key?('setups')
    end
    FileUtils.mkdir_p(path.dirname)
    encoded = "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(path, encoded)
    else
      expect(path.read).to eq(encoded)
    end
  end
end
