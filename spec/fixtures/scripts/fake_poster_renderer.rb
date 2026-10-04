# frozen_string_literal: true

require 'json'

mode = ARGV.length > 1 ? ARGV.first : nil
job = JSON.parse(File.read(ARGV.last))
output = job.fetch('output')

if %w[linger error-child exit-parent continuous continuous-term].include?(mode)
  ready_reader, ready_writer = IO.pipe
  child = fork do
    ready_reader.close
    Signal.trap('TERM', 'IGNORE')
    ready_writer.puts('ready')
    ready_writer.close
    block_reader, block_writer = IO.pipe
    block_writer.sync = true
    block_reader.read
  end
  ready_writer.close
  ready_reader.gets
  ready_reader.close
  Signal.trap('TERM', 'IGNORE') unless mode == 'continuous'
  $stdout.sync = true
  puts JSON.dump(pid: Process.pid, pgrp: Process.getpgrp, child:)
  exit 7 if mode == 'error-child'
  exit 0 if mode == 'exit-parent'

  loop { $stdout.write('renderer-output' * 1024) } if mode.start_with?('continuous')
  block_reader, block_writer = IO.pipe
  block_writer.sync = true
  block_reader.read
end

if mode == 'verbose-error'
  $stdout.write("#{'x' * 131_072}diagnostic-tail")
  exit 7
end

exit 7 if mode == 'error'
job['argv'] = ARGV[0...-1] if mode == 'argv'

File.binwrite(output.fetch('png'), JSON.dump(job))
File.binwrite(output.fetch('pdf'), "PDF:#{job.dig('text', 'title')}") if output['pdf'] && mode != 'no-pdf'

puts '{"ok":true,"ms":1}'
