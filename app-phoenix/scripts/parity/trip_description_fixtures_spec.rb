# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: trip descriptions as Rails renders them on the trip page' do
  let(:path) { Rails.root.join('app-phoenix/test/fixtures/trips/descriptions.json') }
  let(:now) { Time.utc(2026, 9, 29, 12, 0, 0) }

  def deep(levels) = "#{'<div>' * levels}Auwald#{'</div>' * levels}"

  def trix
    '<h1>Leipzig &amp; the Auwald</h1><div>From the <strong>Rosental</strong> <em>along</em> the ' \
      "<del>Elster</del> Pleiße 🚲<br>two&nbsp;&nbsp;spaces, \"quotes\", 'apostrophes', 3 &lt; 4 &gt; 2\nnext line" \
      '</div><blockquote>Leise<br>rauscht</blockquote><ul><li>Rosental<ul><li>Zoo</li></ul></li><li>' \
      '<a href="https://www.leipzig.de/freizeit?x=1&amp;y=2#auwald">Auwald</a></li></ul><ol><li>Auensee</li>' \
      "</ol><pre>12.3712 51.3391\n12.3801 51.3422</pre>"
  end

  def phoenix_cases
    [
      ['trix', trix], ['plain_text', 'Along the Elster'], ['empty_element', '<div></div>'],
      ['padded', "  <div>padded</div>\n\n"],
      ['http_link', '<div><a href="http://www.leipzig.de/a_(b)">Leipzig</a></div>'],
      ['flow_in_list', '<ol><li><div>Rosental</div><h1>Zoo</h1><pre>Auwald</pre><blockquote><ul><li>Elster</li>' \
                       '</ul></blockquote></li></ol>'],
      ['inline_nesting', '<div><strong><em><del><a href="https://www.leipzig.de">x</a></del></em></strong></div>'],
      ['noahs_ark', "#{'<strong>' * 5}x#{'</strong>y' * 5}"],
      ['pre_inline_newline', "<pre><strong>\nx</strong></pre>"],
      ['entity_lookalikes', '<div>&lt;imes;&amp;lt;</div>'],
      ['href_edge_characters', %(<div><a href="https://www.leipzig.de/'&amp;amp;[]">x</a></div>)],
      ['nbsp_entity', '<div>&nbsp;</div>'], ['deepest', deep(16)],
      ['missing', nil], ['empty', ''], ['blank', " \n "]
    ]
  end

  def rails_cases
    [
      ['raw_nbsp', "<div>x\u00a0y</div>"], ['raw_gt', '<div>a > b</div>'], ['quot_entity', '<div>&quot;q&quot;</div>'],
      ['other_entity', '<div>&copy;</div>'], ['paragraph', '<p>para</p>'], ['uppercase', '<DIV>x</DIV>'],
      ['self_closing_br', '<div>a<br/>b</div>'], ['pre_newline', "<pre>\nx</pre>"], ['crlf', "<div>a\r\nb</div>"],
      ['tab', "<div>a\tb</div>"], ['ideographic_space', "\u3000"],
      ['javascript_link', '<div><a href="javascript:alert(1)">x</a></div>'],
      ['relative_link', '<div><a href="/trips">x</a></div>'],
      ['single_quoted_link', "<div><a href='https://www.leipzig.de'>x</a></div>"],
      ['nested_links', '<div><a href="https://www.leipzig.de"><a href="https://www.leipzig.de/b">x</a></a></div>'],
      ['styled', '<div style="color:red">x</div>'], ['script', '<div><script>alert(1)</script>x</div>'],
      ['comment', '<div><!-- c -->x</div>'], ['orphan_item', '<li>orphan</li>'],
      ['heading_in_heading', '<h1><h1>x</h1></h1>'], ['block_in_inline', '<strong><div>x</div></strong>'],
      ['misnested', '<div><strong>a</div></strong>'], ['text_in_list', '<ul>x<li>y</li></ul>'],
      ['too_deep', deep(17)],
      ['attachment', '<action-text-attachment content-type="image/png" url="https://www.leipzig.de/a.png">' \
                     '</action-text-attachment>'],
      ['trix_figure', '<figure data-trix-attachment="{&quot;contentType&quot;:&quot;image/png&quot;,' \
                      '&quot;url&quot;:&quot;https://www.leipzig.de/a.png&quot;}"></figure>']
    ]
  end

  it 'writes each stored body with the HTML the trip page renders for it' do
    user = create(:user)
    cases = phoenix_cases.map { |c| [*c, 'phoenix'] } + rails_cases.map { |c| [*c, 'rails'] }
    ids = cases.each_index.map { |i| 980_900 + i }
    Trip.insert_all(ids.map do |id|
      { id:, user_id: user.id, name: "case #{id}", started_at: now, ended_at: now + 1.day, created_at: now,
        updated_at: now }
    end)
    stored = cases.zip(ids).reject { |(_, body, _), _| body.nil? }
    ActionText::RichText.insert_all(stored.map do |(_, body, _), id|
      { record_type: 'Trip', record_id: id, name: 'description', body:, created_at: now, updated_at: now }
    end)

    rows = cases.zip(ids).map do |(name, body, expect), id|
      rendered = Trip.find(id).description.body
      { name:, body:, expect:, rendered: rendered.presence&.to_s }
    end

    FixtureRecording.verify(path, "#{Oj.dump({ 'cases' => rows.map(&:stringify_keys) }, mode: :strict, indent: 2)}\n")
    FixtureRecording.verify(path.dirname.join('a12f3a-t04.json'),
                            "#{Oj.dump({ 'cases' => rows.map(&:stringify_keys) }, mode: :strict, indent: 2)}\n")
  end
end
