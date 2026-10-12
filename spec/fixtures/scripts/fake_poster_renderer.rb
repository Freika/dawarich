# frozen_string_literal: true

require 'json'

job = JSON.parse(File.read(ARGV[0]))
output = job.fetch('output')

File.binwrite(output.fetch('png'), JSON.dump(job))
File.binwrite(output.fetch('pdf'), "PDF:#{job.dig('text', 'title')}") if output['pdf']

puts '{"ok":true,"ms":1}'
