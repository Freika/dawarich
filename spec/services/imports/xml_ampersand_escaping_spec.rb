# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::XmlAmpersandEscaping do
  subject(:escaper) { harness.new }

  let(:harness) do
    Class.new do
      include Imports::XmlAmpersandEscaping

      def escape(content)
        escape_raw_ampersands(content)
      end
    end
  end

  def parsed_text(fragment)
    xml = escaper.escape("<root><name>#{fragment}</name></root>")

    Hash.from_xml(xml).dig('root', 'name')
  end

  it 'escapes raw ampersands so extracted text keeps the literal character' do
    expect(parsed_text('Fish & Chips')).to eq('Fish & Chips')
  end

  it 'leaves CDATA sections untouched' do
    expect(parsed_text('<![CDATA[Tom & Jerry]]>')).to eq('Tom & Jerry')
  end

  it 'resolves predefined and numeric entities without double-escaping' do
    expect(parsed_text('Fish &amp; Chips &#38; Salt &#x26; Vinegar')).to eq('Fish & Chips & Salt & Vinegar')
  end

  it 'preserves undefined named entities as literal text' do
    expect(parsed_text('a&nbsp;b &copy; c')).to eq('a&nbsp;b &copy; c')
  end

  it 'escapes numeric references to XML-illegal characters' do
    expect(parsed_text('beep &#2; boop')).to eq('beep &#2; boop')
  end
end
