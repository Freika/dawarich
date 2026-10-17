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

STAMP = /(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)(?:\+00(?::00)?)?/

STARTED, ENDED, BUILT_FROM, BUILT_TO = ARGV.drop(1).map { |arg| Integer(arg) }

def now(found)
  moment = Time.parse("#{found[1]} UTC").to_i
  return '<template>' if BUILT_TO && moment.between?(BUILT_FROM, BUILT_TO)

  '<now>' if moment.between?([STARTED - 60, BUILT_TO.to_i + 1].max, ENDED + 60)
end

case ARGV.fetch(0)
when 'jobs'
  $stdin.each_line { |line| puts JSON.generate(canonical(JSON.parse(line))) unless line.strip.empty? }
when 'rows'
  whole = /\A#{STAMP}\z/
  $stdin.each_line(chomp: true) do |line|
    puts(line.split("\t", -1).map { |field| field.match(whole) { |found| now(found) } || field }.join("\t"))
  end
when 'message'
  puts $stdin.read.gsub(/\s+/, ' ').strip.gsub(STAMP) { now(Regexp.last_match) || Regexp.last_match(0) }
when 'failure'
  puts $stdin.read.scan(/\bERROR ([0-9A-Z]{5}) \(/).flatten.last || 'none'
end
