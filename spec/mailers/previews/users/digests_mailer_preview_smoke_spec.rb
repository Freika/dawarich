# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DigestsMailerPreview, type: :mailer do
  before do
    user = create(:user)
    user.digests.create!(year: 2026, month: 3, period_type: :monthly, distance: 100)
    user.digests.create!(year: 2025, period_type: :yearly, distance: 4287)
  end

  describe '#monthly_digest' do
    it 'renders both html and text parts without raising' do
      mail = described_class.new.monthly_digest

      expect { mail.html_part.body.to_s }.not_to raise_error
      expect { mail.text_part.body.to_s }.not_to raise_error
    end

    it 'produces a non-blank html body without translation-missing markers' do
      mail = described_class.new.monthly_digest

      html = mail.html_part.body.to_s
      expect(html).not_to be_blank
      expect(html).not_to include('translation missing')
    end

    it 'produces a non-blank text body' do
      mail = described_class.new.monthly_digest

      expect(mail.text_part.body.to_s).not_to be_blank
    end
  end

  describe '#year_end_digest' do
    it 'renders both html and text parts without raising' do
      mail = described_class.new.year_end_digest

      expect { mail.html_part.body.to_s }.not_to raise_error
      expect { mail.text_part.body.to_s }.not_to raise_error
    end

    it 'produces a non-blank html body without translation-missing markers' do
      mail = described_class.new.year_end_digest

      html = mail.html_part.body.to_s
      expect(html).not_to be_blank
      expect(html).not_to include('translation missing')
    end

    it 'produces a non-blank text body' do
      mail = described_class.new.year_end_digest

      expect(mail.text_part.body.to_s).not_to be_blank
    end
  end
end
