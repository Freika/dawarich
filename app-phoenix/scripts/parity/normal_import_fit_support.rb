# frozen_string_literal: true

require 'fit4ruby'

module NormalImportFormatsSupport
  module_function

  def fit_import_cases(spec)
    base = DIR.join('fit_reader_standard.input.fit')
    flat = DIR.join('fit_reader_flat.input.fit')
    spec.generate_fit_fixture(base.to_s) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
    spec.generate_flat_record_fit_fixture(flat.to_s) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
    fields = [[253, 4, 134], [0, 4, 133], [1, 4, 133], [2, 2, 132], [6, 2, 132], [73, 4, 134]]
    definition = [64, 0, 0, 20, fields.size].pack('CCCvC') + fields.flatten.pack('C*')
    values = [1_100_000_000, 626_349_397, 159_925_070, 2563, 3250, 4250]
    record = [0].pack('C') + values.pack('VllvvV')
    lap = [65, 0, 0, 19, 1].pack('CCCvC') + [253, 4, 134, 1].pack('C*') + [1_100_000_001].pack('V')
    session = [66, 0, 0, 18, 2].pack('CCCvC') + [253, 4, 134, 5, 1, 0, 2].pack('C*') +
              [1_100_000_002].pack('V') + [1].pack('C')
    specs = [['fit_import_standard', File.binread(base)], ['fit_import_flat', File.binread(flat)],
             ['fit_import_legacy', File.binread(base)], ['fit_import_empty', '']]
    { 'enhanced' => definition + record + lap + session,
      'multiple_sessions' => definition + record + lap + session,
      'no_position' => definition + [0].pack('C') + values.dup.tap { |v| v[1] = 0x7fffffff }.pack('VllvvV'),
      'missing_timestamp' => definition + [0].pack('C') + values.dup.tap { |v| v[0] = 0xffffffff }.pack('VllvvV'),
      'earlier_timestamp' => definition + [0].pack('C') + values.dup.tap { |v| v[0] = 1 }.pack('VllvvV'),
      'laps_fallback' => definition + record + lap }.each do |name, bytes|
      path = DIR.join("fit_import_#{name}.source.fit")
      spec.generate_reader_fit_fixture(path.to_s, base.to_s, bytes)
      specs << ["fit_import_#{name}", File.binread(path)]
      File.delete(path)
    end
    no_device = DIR.join('fit_import_no_device.source.fit')
    spec.generate_fit_fixture_without_device_info(no_device.to_s)
    specs << ['fit_import_no_device', File.binread(no_device)]
    File.delete(no_device)
    { 'data_crc' => -1, 'header_crc' => 12 }.each do |name, index|
      bytes = File.binread(base)
      bytes.setbyte(index, bytes.getbyte(index) ^ 1)
      specs << ["fit_import_#{name}", bytes]
    end
    specs << ['fit_import_truncated', File.binread(base)[0...-10]]
    specs << ['fit_import_bad_later_segment', File.binread(base) + File.binread(base)[0...-10]]
    file_id = fit_message(0, 0, [[0, 1, 0]], [4].pack('C'))
    activity = fit_message(1, 34, [[253, 4, 134], [0, 4, 134]], [1_100_000_010, 1000].pack('VV'))
    early_session = fit_message(2, 18, [[5, 1, 0], [25, 2, 132], [26, 2, 132]], [1, 0, 1].pack('Cvv'))
    standalone_record = fit_message(3, 20, fields, values.pack('VllvvV'))
    standalone_lap = fit_message(4, 19, [[253, 4, 134]], [1_100_000_001].pack('V'))
    extras = { 'real_flat' => file_id + early_session + standalone_record + activity,
      'real_laps' => file_id + standalone_record + standalone_lap + activity,
      'no_type' => activity,
      'no_activity_timestamp' => file_id + standalone_record,
      'duplicate' => file_id + standalone_record + standalone_record + activity,
      'skipped' => file_id + fit_message(3, 20, fields, values.dup.tap { |v|
        v[1] = 0x7fffffff
      }.pack('VllvvV')) + activity,
      'absent_timestamp' => file_id + fit_message(3, 20, fields.drop(1), values.drop(1).pack('llvvV')) + activity,
      'speed_zero' => file_id + fit_message(3, 20, fields, values.dup.tap { |v| v[5] = 0 }.pack('VllvvV')) + activity,
      'speed_fallback' => file_id + fit_message(3, 20, fields, values.dup.tap { |v|
        v[5] = 0xffffffff
      }.pack('VllvvV')) + activity }
    [999, 1000, 1001, 2001].each do |count|
      rows = count.times.map do |i|
        numbers = values.dup
        numbers[0] += i
        numbers[1] += i
        fit_message(3, 20, fields, numbers.pack('VllvvV'))
      end.join
      extras["batch#{count}"] = file_id + rows + activity
    end
    extras.each do |name, data|
      header = "#{[14, 32, 1012, data.bytesize].pack('CCvV')}.FIT"
      crc = Object.new.extend(Fit4Ruby::CRC16)
      header += [crc.compute_crc(StringIO.new(header), 0, header.bytesize)].pack('v')
      bytes = header + data + [crc.compute_crc(StringIO.new(data), 0, data.bytesize)].pack('v')
      specs << ["fit_import_#{name}", bytes]
    end
    specs.map { |name, bytes| [name, bytes, 'UTC'] }
  end

  def fit_message(local, number, fields, values)
    [64 + local, 0, 0, number, fields.size].pack('CCCvC') + fields.flatten.pack('C*') +
      [local].pack('C') + values
  end

  def fit_reader_cases(spec)
    base = DIR.join('fit_reader_standard.input.fit')
    flat = DIR.join('fit_reader_flat.input.fit')
    spec.generate_fit_fixture(base.to_s) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
    spec.generate_flat_record_fit_fixture(flat.to_s) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
    fields = [[253, 4, 134], [0, 4, 133], [1, 4, 133], [2, 2, 132], [6, 2, 132], [73, 4, 134]]
    little = [64, 0, 0, 20, fields.size].pack('CCCvC') + fields.flatten.pack('C*')
    big = [64, 0, 1, 20, fields.size].pack('CCCnC') + fields.flatten.pack('C*')
    values = [1_100_000_000, 626_349_397, 159_925_070, 2563, 3250, 4250]
    entry = [0].pack('C') + values.pack('VllvvV')
    replacement = little + entry + big + [0].pack('C') + values.map { |v| v + 1 }.pack('Nl>l>nnN')
    compressed = little + [128 + 3].pack('C') + values.pack('VllvvV')
    invalid = little + [0].pack('C') + [0xffffffff, 0x7fffffff, 0x7fffffff, 0xffff, 0xffff, 0xffffffff].pack('VllvvV')
    id_fields = [[1, 16, 13], [3, 1, 2]]
    developer_id = [65, 0, 0, 207, id_fields.size].pack('CCCvC') + id_fields.flatten.pack('C*') +
                   [1].pack('C') + ([0] * 17).pack('C*')
    desc_fields = [[0, 1, 2], [1, 1, 2], [2, 1, 2], [3, 6, 7], [4, 1, 2], [14, 2, 132]]
    description_header = [65, 0, 0, 206, desc_fields.size].pack('CCCvC')
    description_fields = desc_fields.flatten.pack('C*')
    description_values = [1, 0, 200, 2].pack('C*')
    description_suffix = [0, 1, 20, 0].pack('C*')
    description = "#{description_header}#{description_fields}#{description_values}extra#{description_suffix}"
    developer = little.dup
    developer.setbyte(0, 96)
    developer += "#{[1, 200, 3, 0].pack('C*')}#{entry}xyz"
    developer = developer_id + description + developer
    specs = [['fit_reader_standard', base], ['fit_reader_flat', flat]]
    { 'endian' => replacement, 'compressed' => compressed, 'invalid' => invalid,
      'developer' => developer }.each do |name, bytes|
      path = DIR.join("fit_reader_#{name}.input.fit")
      spec.generate_reader_fit_fixture(path.to_s, base.to_s, bytes) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      specs << ["fit_reader_#{name}", path]
    end
    sport_definition = [64, 0, 0, 18, 1, 5, 1, 0].pack('CCCvCCCC')
    sport_ids = (0..48).to_a + [53, 62, 64, 76, 77, 254]
    sports = sport_ids.map { |sport| [0, sport].pack('CC') }.join
    path = DIR.join('fit_reader_sports.input.fit')
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      spec.generate_reader_fit_fixture(path.to_s, base.to_s, sport_definition + sports)
    end
    specs << ['fit_reader_sports', path]
    header12 = DIR.join('fit_reader_header12.input.fit')
    source = File.binread(base)
    data = source.byteslice(14, source.byteslice(4, 4).unpack1('V'))
    header = "#{[12, 32, 1012, data.bytesize].pack('CCvV')}.FIT"
    bytes = header + data
    crc = Object.new.extend(Fit4Ruby::CRC16).compute_crc(StringIO.new(bytes), 0, bytes.bytesize)
    FixtureRecording.verify(header12, bytes + [crc].pack('v'))
    specs << ['fit_reader_header12', header12]
    { 'data_crc' => -1, 'header_crc' => 12 }.each do |name, index|
      path = DIR.join("fit_reader_#{name}.input.fit")
      bytes = File.binread(base)
      bytes.setbyte(index, bytes.getbyte(index) ^ 1)
      FixtureRecording.verify(path, bytes)
      specs << ["fit_reader_#{name}", path]
    end
    truncated = DIR.join('fit_reader_truncated.input.fit')
    FixtureRecording.verify(truncated, File.binread(base)[0...-10])
    specs << ['fit_reader_truncated', truncated]
    specs.map { |name, path| capture_fit_reader(spec, name, path) }
  end

  def capture_fit_reader(spec, name, path)
    records = []
    spec.allow_any_instance_of(Fit4Ruby::FitFileEntity).to spec.receive(:check)
    spec.allow_any_instance_of(Fit4Ruby::FitMessageRecord).to spec.receive(:read).and_wrap_original do |method, *args|
      method.call(*args)
      decoder = method.receiver
      if [18, 19, 20].include?(decoder.global_message_number)
        definition = decoder.instance_variable_get(:@definition)
        wanted = %w[timestamp start_time position_lat position_long altitude speed enhanced_speed sport first_lap_index
                    num_laps message_index]
        fields = definition.data_fields.filter_map do |field|
          next unless wanted.include?(field.name)

          value = decoder.message_record[decoder.send(:to_bd_field_name, field.name)].snapshot
          value = field.to_machine(value)
          value = value.to_i if value.is_a?(Time)
          [field.name, value]
        end.to_h
        records << { 'number' => decoder.global_message_number, 'fields' => fields }
      end
    end
    error = nil
    begin
      Fit4Ruby.read(path.to_s)
    rescue StandardError => e
      error = { 'class' => e.class.name, 'message' => e.message }
    end
    { 'name' => name, 'input' => path.basename.to_s, 'records' => fit_float_bits(records), 'error' => error }
  end

  def fit_float_bits(value)
    case value
    when Float then { '__float64__' => [value].pack('G').unpack1('H*') }
    when Array then value.map { |item| fit_float_bits(item) }
    when Hash then value.transform_values { |item| fit_float_bits(item) }
    else value
    end
  end
end
