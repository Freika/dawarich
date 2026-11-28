# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotificationsHelper, type: :helper do
  describe '#notification_snippet' do
    def snippet(content)
      helper.notification_snippet(build(:notification, content:))
    end

    it 'drops markup and keeps the words' do
      text = snippet('Import <a href="/imports/1">Open</a> failed <script>alert(1)</script>')

      expect(text).to include('Import', 'failed')
      expect(text).not_to include('<a', '<script')
    end

    it 'leaves out link labels, because the whole bell item is already a link' do
      content = 'Import failed. <a href="/imports/1">Open import and recovery options</a>'

      expect(snippet(content)).to eq('Import failed.')
    end

    it 'leaves out the contents of a script element' do
      expect(snippet('Hello <script>alert(1)</script>there')).to eq('Hello there')
    end

    it 'stops before the stack trace of an error' do
      expect(snippet("Export failed: boom, stacktrace: app/models/x.rb:1\napp/y.rb:2")).to eq('Export failed: boom,')
    end

    it 'is at most 120 characters' do
      expect(snippet('word ' * 100).length).to be <= 120
    end

    it 'collapses whitespace' do
      expect(snippet("one\n\n   two")).to eq('one two')
    end

    it 'shows an ampersand once when rendered' do
      rendered = ERB::Util.html_escape(snippet('Import Tom &amp; Jerry.gpx failed'))

      expect(rendered).to eq('Import Tom &amp; Jerry.gpx failed')
    end

    it 'never turns escaped text back into markup when rendered' do
      rendered = ERB::Util.html_escape(snippet('joined &lt;b&gt;bold&lt;/b&gt; family'))

      expect(rendered).not_to include('<b>')
      expect(rendered).to include('&lt;b&gt;')
    end
  end
end
