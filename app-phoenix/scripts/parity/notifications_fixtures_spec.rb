# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the notification pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:fixtures) { Rails.root.join('app-phoenix/test/fixtures') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }

  def write_json(name, data) = File.write(fixtures.join(name), "#{JSON.pretty_generate(data)}\n")

  it 'writes the sanitize corpus' do
    inputs = [
      'plain text & more', 'B9 safe detail <script>window.b9Xss=true</script>',
      "joined the family '<script>window.xss=true</script><img src=x onerror=alert(1)>'",
      '<a href="https://dawarich.app/x?a=1&b=2" target="_blank" onclick="x()">link</a>',
      '<a href="javascript:alert(1)">js</a>', '<a href="JaVaScRiPt:alert(1)">js</a>',
      '<a href="java&#x09;script:alert(1)">js</a>', '<a href="java&#58script:alert(1)">js</a>',
      '<a href="javascript&colon;alert(1)">js</a>', '<a href="&amp;#106avascript:alert(1)">js</a>',
      '<a href="/relative path">rel</a>',
      '<a href="mailto:hi@dawarich.app" name="n m">mail</a>', '<a href="a"b">quote</a>',
      '<img src="data:image/png;base64,AAAA" alt="ok">', '<img src="data:text/html;base64,AAAA">',
      '<img src="data&#58;text/html,x">', '<img src="  " alt="blank">', '<img src="x" width="10" height="5" title="t">',
      '<p style="color:red" class="c">styled</p>', '<div><span lang="de" xml:lang="de">Hallo</span></div>',
      '<ul><li>one<li>two</ul>', '<b>bold <i>both</b> italic</i>', '<table><tr><td>cell</td></tr></table>',
      '<iframe src="https://evil.example"></iframe>after', '<style>p{color:red}</style>kept',
      '<svg><a href="x">in svg</a></svg>tail', '<math><mi>x</mi></math>tail', '<!-- comment -->visible',
      '<template><b>t</b></template>after', '<noscript><b>n</b></noscript>after', 'Line<br>break<br/>again',
      '<h1>H</h1><h6>H6</h6><hr>', '<code>x &lt; y</code>', '<pre>  pre  </pre>',
      '<time datetime="2026-09-28">today</time>',
      '<blockquote cite="javascript:x">q</blockquote>', '<form action="/x"><input value="v"></form>text',
      'a < b and c > d', 'unclosed <b>bold', '<del>d</del><ins>i</ins><mark>m</mark><sub>s</sub><sup>s</sup>',
      '<a href="https://x.example/?q=a b">space</a>', '<abbr title="t" abbr="a">A</abbr><cite>c</cite><dfn>d</dfn>'
    ]
    corpus = inputs.map { |input| { input:, output: ApplicationController.helpers.sanitize(input).to_s } }
    write_json('sanitize.json', corpus)
  end

  it 'writes the distance-in-words corpus' do
    offsets = [0, 29, 30, 59, 89, 90, 119, 2669, 2670, 5369, 5370, 86_369, 86_370, 151_169, 151_170, 2_591_969,
               2_591_970, 5_183_969, 5_183_970, 31_535_969, 31_536_000, 47_304_000, 63_072_000, 94_608_000,
               126_230_400, 315_360_000]
    corpus = travel_to(now) do
      %w[en de].flat_map do |locale|
        offsets.map do |seconds|
          words = I18n.with_locale(locale) { ApplicationController.helpers.relative_distance_in_words(now - seconds) }
          { locale:, seconds:, words: }
        end
      end
    end
    write_json('time_ago.json', corpus)
  end
end
