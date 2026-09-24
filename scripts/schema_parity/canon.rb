# frozen_string_literal: true

require 'json'
require 'time'

$stdin.set_encoding(Encoding::UTF_8)
$stdout.set_encoding(Encoding::UTF_8)

def canonical(value)
  case value
  when Hash then value.sort.to_h.transform_values { |item| canonical(item) }
  when Array then value.map { |item| canonical(item) }
  else value
  end
end

case ARGV.fetch(0)
when 'jobs'
  $stdin.each_line { |line| puts JSON.generate(canonical(JSON.parse(line))) unless line.strip.empty? }
when 'rows'
  from = Integer(ARGV.fetch(1)) - 60
  to = Integer(ARGV.fetch(2)) + 60
  stamp = /\A(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)(?:\+00(?::00)?)?\z/
  $stdin.each_line(chomp: true) do |line|
    fields = line.split("\t", -1).map do |field|
      moment = field.match(stamp) { |found| Time.parse("#{found[1]} UTC").to_i }
      moment&.between?(from, to) ? '<now>' : field
    end
    puts fields.join("\t")
  end
when 'failure'
  puts $stdin.read.scan(/\bERROR ([0-9A-Z]{5}) \(/).flatten.last || 'none'
end
