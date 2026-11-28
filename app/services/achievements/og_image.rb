# frozen_string_literal: true

require 'erb'
require 'open3'
require 'timeout'

module Achievements
  class OgImage
    WIDTH = 1200
    HEIGHT = 630
    RENDER_TIMEOUT = 10
    CONVERTER = 'rsvg-convert'
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
      svg_data = svg
      command = [CONVERTER, '-f', 'png', '-w', WIDTH.to_s, '-h', HEIGHT.to_s]
      Open3.popen3(*command, pgroup: true) do |stdin, stdout, stderr, wait_thr|
        writer = Thread.new do
          stdin.write(svg_data)
          stdin.close
        end
        output_reader = Thread.new { stdout.read }
        error_reader = Thread.new { stderr.read }

        begin
          png, errors, status = Timeout.timeout(RENDER_TIMEOUT) do
            writer.value
            [output_reader.value, error_reader.value, wait_thr.value]
          end
          raise "Achievement OG image render failed: #{errors}" unless status.success?

          png
        rescue StandardError
          begin
            Process.kill('KILL', -wait_thr.pid) if wait_thr.alive?
          rescue Errno::ESRCH
            nil
          end
          raise
        ensure
          stdin.close unless stdin.closed?
          writer.join
          output_reader.join
          error_reader.join
        end
      end
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
