# frozen_string_literal: true

module YearlyDigests
  class ChartImageGenerator
    def initialize(digest, distance_unit: 'km')
      @digest = digest
      @distance_unit = distance_unit
    end

    def call
      html = render_chart_html
      generate_image(html)
    end

    private

    attr_reader :digest, :distance_unit

    def render_chart_html
      ApplicationController.render(
        template: 'yearly_digests/chart',
        layout: false,
        assigns: {
          monthly_distances: digest.monthly_distances,
          distance_unit: distance_unit
        }
      )
    end

    def generate_image(html)
      grover = Grover.new(
        html,
        format: 'png',
        viewport: { width: 600, height: 320 },
        wait_until: 'networkidle0'
      )
      grover.to_png
    end
  end
end
