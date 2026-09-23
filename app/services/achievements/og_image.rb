# frozen_string_literal: true

require 'erb'
require 'open3'
require 'timeout'

module Achievements
  class OgImage
    WIDTH = 1200
    HEIGHT = 630
    RENDER_TIMEOUT = 10
    TEMPLATE = Rails.root.join('app/services/achievements/og_image.svg.erb')
    ACCENTS = {
      'common' => '#aeb8c5',
      'rare' => '#58b6ff',
      'epic' => '#bb85ef',
      'legendary' => '#ffc266'
    }.freeze

    def initialize(set)
      @set = set
    end

    def call
      stdout, stderr, status = Timeout.timeout(RENDER_TIMEOUT) do
        Open3.capture3('rsvg-convert', '-f', 'png', '-w', WIDTH.to_s, '-h', HEIGHT.to_s, stdin_data: svg)
      end
      raise "Achievement OG image render failed: #{stderr}" unless status.success?

      stdout
    end

    def svg
      ERB.new(TEMPLATE.read).result(binding)
    end

    private

    def attributes
      @attributes ||= @set.card_attributes
    end

    def accent
      ACCENTS.fetch(@set.rarity.to_s.downcase, ACCENTS['common'])
    end

    def muted_accent
      @set.locked? ? '#68717d' : accent
    end

    def rarity_label
      I18n.t("achievements.cards.rarity.#{@set.rarity.to_s.downcase}")
    end

    def status_label
      return I18n.t('achievements.cards.metric.not_yet_explored') if @set.locked?
      if !@set.completed? && attributes[:earned_label] == attributes[:metric_label]
        return I18n.t('achievements.cards.status.in_progress')
      end

      attributes[:earned_label]
    end

    def title_lines
      @title_lines ||= begin
        words = @set.name.split(/\s+/)
        lines = ['']
        words.each do |word|
          if lines.size == 1 && !lines.last.empty? && (lines.last.length + word.length + 1) > 21
            lines << word
          else
            lines[-1] = [lines.last, word].reject(&:empty?).join(' ')
          end
        end
        lines[-1] = "#{lines[-1].first(28)}…" if lines[-1].length > 29
        lines
      end
    end

    def escape(value)
      ERB::Util.html_escape(value.to_s)
    end
  end
end
