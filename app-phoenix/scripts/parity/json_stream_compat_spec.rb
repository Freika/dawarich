# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: lexical edges of Oj.load in compat mode, as Imports::FileLoader reads JSON' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/imports/geojson/compat-lexical.json') }

  let(:cases) do
    {
      'prefix_block' => '/* root */{"altitude":1}',
      'prefix_line' => "// root\n{\"altitude\":1}",
      'suffix_block' => '{"altitude":1}/* end */',
      'suffix_line' => '{"altitude":1}// end',
      'inner_block' => '{"altitude":/* value */1}',
      'inner_line' => "{\"altitude\":// value\n1}",
      'exponent_missing' => '{"altitude":1e}',
      'exponent_sign' => '{"altitude":1e+}',
      'exponent_bad' => '{"altitude":1eX}',
      'dot_missing' => '{"altitude":1.}',
      'dot_exp' => '{"altitude":1.e2}',
      'leading_zero' => '{"altitude":01}',
      'leading_plus' => '{"altitude":+1}',
      'empty' => '',
      'two_docs' => '{} {}',
      'whitespace_end' => "{\"altitude\":1}\n \t"
    }
  end

  def outcome(name, raw)
    { name: name, input: raw, outcome: 'ok', value: Oj.load(raw, mode: :compat) }
  rescue StandardError => e
    { name: name, input: raw, outcome: 'error', error: e.class.name, message: e.message }
  end

  it 'records every case' do
    output = cases.map { |name, raw| outcome(name, raw) }
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(output)}\n")
    expect(output.size).to eq(cases.size)
  end
end
