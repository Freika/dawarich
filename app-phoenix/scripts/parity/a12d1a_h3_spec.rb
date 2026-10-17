# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: A12d1a H3 v3 cells' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/a12d1a/h3.json') }
  let(:pentagons) { [4, 14, 24, 38, 49, 58, 63, 72, 83, 97, 107, 117] }
  let(:offsets) { [[0.01, 0], [-0.01, 0], [0, 0.01], [0, -0.01], [0.5, 0.5], [-0.5, -0.5], [0.3, -0.7]] }
  let(:fixed) do
    [[0.0, 0.0], [90.0, 0.0], [-90.0, 0.0], [89.9999, 179.9999], [-89.9999, -179.9999], [0.0, 180.0],
     [0.0, -180.0], [12.34, 179.999999], [-12.34, -179.999999], [52.107902115161316, 14.452712811406352],
     [51.3397, 12.3731], [52.52, 13.405], [-33.8688, 151.2093], [64.1466, -21.9426], [-54.8019, -68.303]]
  end

  it 'writes or matches h3.json, byte-identical on a second capture' do
    first = Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2)
    expect(Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2)).to eq(first)

    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "#{first}\n")
    else
      expect("#{first}\n").to eq(path.read)
    end
  end

  def capture
    cases = coordinates.map do |lat, lng|
      { 'lat' => lat, 'lng' => lng, 'cells' => (0..15).map { |res| H3.from_geo_coordinates([lat, lng], res).to_s(16) } }
    end
    { 'gem' => Gem.loaded_specs.fetch('h3').version.to_s, 'cases' => cases }
  end

  def coordinates
    centers = (0..121).map { |cell| H3.to_geo_coordinates((1 << 59) | (cell << 45) | 0x1FFF_FFFF_FFFF) }
    around = pentagons.flat_map do |cell|
      lat, lng = centers[cell]
      offsets.map { |dlat, dlng| [(lat + dlat).clamp(-90.0, 90.0), wrap(lng + dlng)] }
    end
    random = Random.new(20_261_003)
    scattered = Array.new(600) { [(random.rand * 180.0) - 90.0, (random.rand * 360.0) - 180.0] }
    centers + around + scattered + fixed
  end

  def wrap(lng)
    return lng - 360 if lng > 180
    return lng + 360 if lng < -180

    lng
  end
end
