# frozen_string_literal: true

require 'net/http'
require 'uri'

module Dawarich
  # Rack middleware that wraps a local metrics endpoint (Yabeda::Prometheus::Exporter)
  # and appends metrics fetched from a remote in-network endpoint (typically the
  # Sidekiq container's WEBrick exporter). The combined response is served from a
  # single external URL — used when the remote endpoint cannot be exposed publicly.
  #
  # Failure mode: if the remote fetch fails (network error, non-200), the middleware
  # logs a warning and returns local metrics only. Prometheus sees a momentary gap
  # in remote metrics rather than a scrape failure.
  class AggregatingMetrics
    HELP_PREFIX = '# HELP '
    TYPE_PREFIX = '# TYPE '
    LOCAL_PROCESS = 'web'
    REMOTE_PROCESS = 'sidekiq'
    PROCESS_LABEL = 'process'
    SAMPLE_LINE = /\A([a-zA-Z_:][a-zA-Z0-9_:]*)(\{.*?\})?(\s+.*)\z/
    PROCESS_LABEL_PRESENT = /[{,]process="/

    def initialize(local_app, remote_url:, remote_user:, remote_password:, timeout: 5)
      @local_app = local_app
      @remote_url = URI(remote_url)
      @remote_user = remote_user
      @remote_password = remote_password
      @timeout = timeout
    end

    def call(env)
      status, headers, body = @local_app.call(env)
      return [status, headers, body] unless status == 200

      local = read_body(body)
      remote = fetch_remote_metrics
      [200, { 'Content-Type' => 'text/plain; version=0.0.4' }, [merge(local, remote)]]
    end

    private

    def fetch_remote_metrics
      Net::HTTP.start(@remote_url.host, @remote_url.port,
                      open_timeout: @timeout, read_timeout: @timeout) do |http|
        req = Net::HTTP::Get.new(@remote_url.request_uri)
        req.basic_auth(@remote_user, @remote_password)
        res = http.request(req)
        return res.body if res.is_a?(Net::HTTPSuccess)

        Rails.logger.warn("[AggregatingMetrics] sidekiq /metrics returned #{res.code}") if defined?(Rails.logger)
        ''
      end
    rescue StandardError => e
      Rails.logger.warn("[AggregatingMetrics] sidekiq /metrics fetch failed: #{e.message}") if defined?(Rails.logger)
      ''
    end

    # Concatenates local and remote bodies. Deduplicates `# HELP <name> ...` and
    # `# TYPE <name> ...` lines so the same metric name doesn't appear twice in
    # metadata.
    #
    # Both processes register some collectors independently, so the same metric
    # name and label set can arrive from each with a different value — which
    # OpenMetrics forbids and strict ingesters reject. Those samples, and only
    # those, get a `process` label naming where they came from, so the series
    # stay distinct without renaming anything that isn't ambiguous.
    def merge(local, remote)
      return local if remote.empty?

      collisions = sample_identities(local) & sample_identities(remote)

      seen = Set.new
      out = String.new

      { LOCAL_PROCESS => local, REMOTE_PROCESS => remote }.each do |process, body|
        body.each_line do |line|
          line = "#{line}\n" unless line.end_with?("\n")
          if line.start_with?(HELP_PREFIX) || line.start_with?(TYPE_PREFIX)
            metric_name = line.split(/\s+/, 4)[2]
            prefix = line.start_with?(HELP_PREFIX) ? HELP_PREFIX : TYPE_PREFIX
            key = "#{prefix}#{metric_name}"
            next unless seen.add?(key)

            out << line
            next
          end

          out << disambiguate(line, process, collisions)
        end
      end

      out
    end

    def sample_identities(body)
      body.each_line.filter_map { |line| identity_of(line) }.to_set
    end

    def identity_of(line)
      return if line.start_with?('#')

      match = SAMPLE_LINE.match(line.strip)
      return if match.nil?

      labels = match[2]
      labels = nil if labels == '{}'

      "#{match[1]}#{labels}"
    end

    def disambiguate(line, process, collisions)
      identity = identity_of(line)
      return line unless collisions.include?(identity)

      match = SAMPLE_LINE.match(line.strip)
      name = match[1]
      labels = match[2]
      value = match[3]
      return line if PROCESS_LABEL_PRESENT.match?(labels.to_s)

      label = %(#{PROCESS_LABEL}="#{process}")
      labels = if labels.nil? || labels == '{}'
                 "{#{label}}"
               else
                 "{#{label},#{labels[1..]}"
               end

      "#{name}#{labels}#{value}\n"
    end

    def read_body(body)
      buf = +''
      body.each { |chunk| buf << chunk }
      body.close if body.respond_to?(:close)
      buf
    end
  end
end
