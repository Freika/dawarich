# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the trips pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/trips') }
  let(:now) { Time.utc(2026, 9, 29, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:helper) { ApplicationController.helpers }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before { FileUtils.mkdir_p(dir.join('pages')) }

  def write_json(name, data)
    encoded = "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join(name), encoded)
    else
      expect(JSON.parse(dir.join(name).read)).to eq(JSON.parse(encoded))
    end
  end

  def utc(text) = Time.iso8601(text)

  context 'A8 remaining trips' do
    let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }
    let(:dir) { super().join('remaining') }

    around do |example|
      detailed = Rails.application.env_config['action_dispatch.show_detailed_exceptions']
      Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = false
      example.run
    ensure
      Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = detailed
    end

    def remaining_user(id)
      user = create(:user, id:, email: "a8r-#{id}@example.invalid", changelog_consent: :declined)
      user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                          api_key: "a8r-k-#{id}", plan: User.plans[:pro])
      user.reload
    end

    def remaining_stamps = { created_at: now - 2.hours, updated_at: now - 2.hours }

    def remaining_trip(user, id, **attrs)
      Trip.insert!({ id:, user_id: user.id, name: 'Auwald', started_at: utc('2026-10-02T22:30:00Z'),
                     ended_at: utc('2026-10-04T01:00:00Z'), distance: 1200, visited_countries: ['Germany'],
                     path: 'LINESTRING(12.3712 51.3391, 12.3801 51.3422)' }.merge(remaining_stamps).merge(attrs))
      Trip.find(id)
    end

    def remaining_note(user, trip, id, body, date: '2026-10-03', **attrs)
      Note.insert!({ id:, user_id: user.id, attachable_type: 'Trip', attachable_id: trip.id,
                     noted_at: utc("#{date}T12:00:00Z"), body: }.merge(remaining_stamps).merge(attrs))
      Note.find(id)
    end

    def remaining_plan(user, trip, id, state)
      TripSource.insert!({ id:, user_id: user.id, provider: 'trek', base_url: 'https://trek.example.invalid',
                           status: 0 }.merge(remaining_stamps))
      trip.update_columns(trip_source_id: id, source_identifier: 'Auwald / &', source_status: state == :stopped ? 1 : 0,
                          source_synced_at: now - 1.hour)
      day = trip.planned_days.create!(id:, date: '2026-10-03', position: 2, title: 'Leipzig <&>',
                                      notes: "From TREK\nAlong the Elster", **remaining_stamps)
      trip.planned_days.create!(id: id + 1, date: '2026-10-04', position: 1, **remaining_stamps)
      day.planned_stops.create!(id:, name: 'Unlocated', position: 1, **remaining_stamps)
      day.planned_stops.create!(id: id + 1, name: 'Auensee', position: 2, latitude: 51.3391, longitude: 12.3712,
                                address: 'Leipzig', starts_at: '09:00', ends_at: '10:00', transport_mode: 'walking',
                                category: 'Lake', duration_minutes: 60, notes: "Quiet\nWater", **remaining_stamps)
      day.planned_stops.create!(id: id + 2, name: 'Rosental', position: 3, latitude: 51.3422, longitude: 12.3801,
                                transport_mode: 'unlisted_mode', **remaining_stamps)
      day.planned_stops.create!(id: id + 3, name: 'Zero', position: 4, latitude: 0, longitude: 0, **remaining_stamps)
      day.planned_day_notes.create!(id:, position: 1, body: 'Source detail', noted_at: '09:30', **remaining_stamps)
      trip.planned_reservations.create!(id:, planned_day: day, title: 'Train <&>', reservation_type: 'train',
                                        starts_at: now, ends_at: now + 1.hour, location: 'Leipzig', status: 'confirmed',
                                        notes: 'Window seat', **remaining_stamps)
      trip.planned_reservations.create!(id: id + 1, title: 'Loose reservation', status: 'unlisted_status',
                                       **remaining_stamps)
      trip.planned_accommodations.create!(id:, name: 'Stay', latitude: 51.34, longitude: 12.37,
                                          starts_on: '2026-10-03', ends_on: '2026-10-04', notes: 'Rest',
                                         **remaining_stamps)
      trip.planned_travellers.create!(id:, name: 'Traveller <&>', **remaining_stamps)
      trip.planned_unplanned_places.create!(id:, name: 'Loose place', position: 1, latitude: 51.35,
                                            longitude: 12.38, address: 'Leipzig', **remaining_stamps)
      if %i[synced edited].include?(state)
        body = "From TREK\nAlong the Elster"
        remaining_note(user, trip, id, state == :synced ? body : "#{body}\nEdited",
                       source_digest: Note.body_digest(body))
      end
      trip.reload
    end

    def remaining_rows(model, scope)
      scope.order(model.primary_key).map do |row|
        row.attributes.transform_values do |value|
          if value.respond_to?(:utc)
            value.utc.iso8601(6)
          elsif value.is_a?(Date)
            value.iso8601
          elsif value.is_a?(BigDecimal)
            value.to_s('F')
          elsif value.is_a?(ActionText::Content)
            value.to_html
          elsif value.respond_to?(:coordinates)
            value.coordinates
          else
            value
          end
        end
      end
    end

    def remaining_graph(user, id)
      range = id...id + 20
      models = [Trip, Note, PlannedDay, PlannedStop, PlannedDayNote, PlannedReservation,
                PlannedAccommodation, PlannedTraveller, PlannedUnplannedPlace, Point, Export, RouteVideo, Poster]
      graph = models.to_h { |model| [model.table_name, remaining_rows(model, model.where(id: range))] }
      graph['action_text_rich_texts'] = remaining_rows(
        ActionText::RichText, ActionText::RichText.where(record_type: 'Trip', record_id: range)
      )
      graph['shared_links'] = remaining_rows(SharedLink, SharedLink.where(resource_id: range))
      graph['trip_sources'] = TripSource.where(id: range).order(:id).map do |source|
        source.attributes.slice('id', 'user_id', 'provider', 'base_url', 'status', 'importing')
      end
      graph['actor'] =
        { id: user.id, settings: user.settings, plan: user.plan, active_until: user.active_until.utc.iso8601(6) }
      graph
    end

    def remaining_queue(id)
      { jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue] } },
        sidekiq: Sidekiq::ActiveJob::Wrapper.jobs.map do |job|
          { job: job['wrapped'], args: job['args'].first['arguments'], queue: job['queue'] }
        end,
        outbox: JobOutbox.where(aggregate_id: id...id + 20).order(:command_type, :aggregate_id).map do |row|
          row.attributes.slice('command_type', 'command_version', 'payload', 'metadata', 'aggregate_id',
                               'dedupe_key', 'state').merge('scheduled_at' => row.scheduled_at.utc.iso8601(6))
        end }
    end

    def remaining_request(user, method, path, params, accept)
      Rails.cache.clear
      reset!
      sign_in user
      get '/settings/visits'
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    end

    def remaining_html(body)
      body = body.gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
                 .gsub(/(name="(?:csrf-token|csp-nonce)" content=")[^"]*/, '\1CSRF')
      if body.include?('<div class="flex w-full min-w-0 gap-5">')
        body = body.split('<div class="flex w-full min-w-0 gap-5">', 2).last
                   .split("\n        </div>\n      </div>\n      <div class=\"px-4", 2).first
      end
      body
    end

    def remaining_response(name, error = nil)
      html = error ? '' : remaining_html(response.body)
      path = dir.join("pages/#{name}.html")
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        File.write(path, html)
      else
        expect(path.read).to eq(html), name
      end
      textareas = html.scan(%r{<textarea\b[^>]*>(.*?)</textarea>}m).flatten.map do |raw|
        { raw:, value: Nokogiri::HTML5.fragment("<textarea>#{raw}</textarea>").at_css('textarea').content }
      end
      doc = Nokogiri::HTML5.fragment(html)
      { name:, status: error ? nil : response.status, media_type: error ? nil : response.media_type,
        headers: error ? {} : response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control'),
        location: error ? nil : response.location, flash: error ? {} : flash.to_hash,
        error: error && { class: error.class.name, message: error.message.gsub(Rails.root.to_s, 'RAILS_ROOT')
                                                                 .gsub(/0x[0-9a-f]+/, 'OBJECT_ID') },
        streams: doc.css('turbo-stream').map { { action: _1['action'], target: _1['target'] } },
        textareas:,
        errors: doc.css('#error_explanation li, .alert-error').map { _1.text.strip },
        controls: doc.css('form, input, textarea, trix-editor, button, [data-controller]').map do |node|
          { tag: node.name, attributes: node.attributes.transform_values(&:value) }
        end }
    end

    def remaining_scenarios
      valid = { name: 'New Auwald', started_at: '2026-10-03T09:00', ended_at: '2026-10-04T19:00' }
      dates = { blank: { started_at: '', ended_at: '' }, missing: {},
                equal: { started_at: '2026-10-03T09:00', ended_at: '2026-10-03T09:00' },
                reversed: { started_at: '2026-10-04T09:00', ended_at: '2026-10-03T09:00' },
                bad_date: { started_at: 'not-a-date', ended_at: '2026-10-04T09:00' },
                dst_gap: { started_at: '2026-03-29T02:30', ended_at: '2026-03-29T04:30' },
                dst_fold: { started_at: '2026-10-25T02:30', ended_at: '2026-10-25T04:30' } }
      cases = [{ name: 'new', action: :new }, { name: 'edit', action: :edit }]
      %i[sidekiq oban].each do |owner|
        cases << { name: "create_#{owner}", action: :create, attrs: valid, owner:, expected: 302 }
        cases << { name: "create_ignored_demo_#{owner}", action: :create, attrs: valid.merge(demo: true), owner:,
                   expected: 302 }
        dates.each do |name, attrs|
          cases << { name: "create_#{name}_#{owner}", action: :create, attrs: { name: 'Dates' }.merge(attrs), owner:,
                     expected: %i[dst_gap dst_fold].include?(name) ? 302 : 422 }
        end
        cases << { name: "create_blank_name_#{owner}", action: :create, attrs: valid.merge(name: ''), owner:,
                   expected: 422 }
        cases << { name: "create_missing_template_#{owner}", action: :create, attrs: { name: '' }, owner:,
                   accept: 'text/vnd.turbo-stream.html', error: 'ActionView::MissingTemplate' }
        embedded = '<action-text-attachment content-type="image/png" ' \
                   'url="https://example.invalid/synthetic.png"></action-text-attachment>'
        [false, true].each do |demo|
          { name: { name: 'Changed Auwald' }, noop: { name: 'Auwald' },
            date: { started_at: '2026-10-03T10:00' }, empty: { description: '' },
            finite: { description: '<div>Auwald &amp; <strong>Elster</strong><br>Leipzig</div>' },
            embedded: { description: embedded } }.each do |name, attrs|
            cases << { name: "update_#{name}_#{demo ? 'demo' : 'ordinary'}_#{owner}", action: :update,
                       attrs:, demo:, owner:, description: '<div>Before</div>', expected: 303 }
          end
          cases << { name: "destroy_#{demo ? 'demo' : 'ordinary'}_#{owner}", action: :destroy,
                     demo:, owner:, plan: :synced, description: '<div>Before</div>', graph: true, expected: 303 }
        end
        cases << { name: "update_invalid_#{owner}", action: :update, attrs: { name: '', ended_at: '' },
                   owner:, expected: 422 }
        cases << { name: "update_equal_#{owner}", action: :update, attrs: dates[:equal], owner:, expected: 422 }
        cases << { name: "update_blank_start_#{owner}", action: :update, attrs: { started_at: '' }, owner:,
                   expected: 422 }
        cases << { name: "demo_recalculate_#{owner}", action: :recalculate, owner:, demo: true, age: nil,
                   expected: 302 }
        cases << { name: "demo_show_missing_#{owner}", action: :show, owner:, demo: true, show: :nil_path,
                   expected: 200 }
        [nil, 59, 60, 61].product(%w[text/html text/vnd.turbo-stream.html]).each do |age, accept|
          cases << { name: "recalculate_#{age || 'nil'}_#{accept == 'text/html' ? 'html' : 'stream'}_#{owner}",
                     action: :recalculate, owner:, age:, accept:, expected: accept == 'text/html' ? 302 : 200 }
        end
        %w[gpx json csv].product(['Auwald', 'Über Auwald', '!!!', '']).each_with_index do |(format, title), i|
          cases << { name: "export_#{format}_#{i}_#{owner}", action: :export, owner:, format:, title:,
                     expected: format == 'csv' ? 422 : 302 }
        end
        %i[create update recalculate show].product(%i[enqueue sql]).each do |action, fault|
          attrs = action == :create ? valid : { started_at: '2026-10-03T10:00' }
          error = fault == :enqueue ? 'RuntimeError' : 'ActiveRecord::StatementInvalid'
          cases << { name: "#{action}_#{fault}_failure_#{owner}", action:, owner:, attrs:, fault:, error:,
                     missing: action == :show }
        end
        %i[nil_path empty_path nil_distance zero_distance empty_countries hash_countries no_stats stats
           future_import future_plain repeat].each do |state|
          cases << { name: "show_#{state}_#{owner}", action: :show, owner:, show: state, expected: 200 }
        end
      end
      %i[active stopped synced edited future future_stats toggle no_source no_identifier].each do |plan|
        %i[show edit index].each do |action|
          cases << { name: "plan_#{plan}_#{action}", action:, plan:, owner: :oban, expected: 200 }
        end
      end
      cases << { name: 'managed_update', action: :update, plan: :active, attrs: { name: 'Submitted despite readonly' },
                 expected: 303 }
      bodies = { plain: "Auwald <&> 'quoted'", lf: "\nAuwald", lfs: "\n\nAuwald", unicode: 'É🌳',
                 blank: '', max: 'é' * 10_000, over: 'é' * 10_001 }
      bodies.each do |name, body|
        %i[note_create note_update].product(%w[text/html text/vnd.turbo-stream.html]).each do |action, accept|
          cases << { name: "#{action}_#{name}_#{accept == 'text/html' ? 'html' : 'stream'}", action:, body:, accept:,
                     expected: accept == 'text/html' ? 302 : 200 }
        end
        if %i[plain lf lfs unicode].include?(name)
          cases << { name: "note_document_#{name}", action: :show, body:, note: true, expected: 200 }
        end
      end
      %w[2026-10-02 2026-10-03 2026-10-04 2026-10-05 bad-date].product(
        %w[text/html text/vnd.turbo-stream.html]
      ).each do |date, accept|
        expected = accept == 'text/html' ? 302 : 200
        expected = 422 if date == 'bad-date' && accept != 'text/html'
        cases << { name: "note_date_#{date}_#{accept == 'text/html' ? 'html' : 'stream'}", action: :note_create,
                   body: 'Date boundary', date:, accept:, expected: }
      end
      cases << { name: 'note_upsert', action: :note_create, note: true, body: 'Upserted', expected: 200 }
      cases << { name: 'note_race', action: :note_create, note: true, body: 'Second writer', race: true, expected: 200 }
      %w[text/html text/vnd.turbo-stream.html].each do |accept|
        cases << { name: "note_delete_#{accept == 'text/html' ? 'html' : 'stream'}", action: :note_destroy,
                   accept:, expected: accept == 'text/html' ? 302 : 200 }
      end
      %i[edit update destroy show note_update note_destroy].each do |action|
        cases << { name: "foreign_#{action}", action:, foreign: true, attrs: { name: 'Rejected' }, body: 'Rejected',
                   expected: 404 }
      end
      cases
    end

    def remaining_setup(user, id, entry)
      return if %i[new create].include?(entry[:action])

      target = entry[:foreign] && !entry[:action].to_s.start_with?('note_') ? remaining_user(user.id + 100_000) : user
      trip = remaining_trip(target, id, demo: entry.fetch(:demo, false), name: entry.fetch(:title, 'Auwald'))
      remaining_plan(user, trip, id, entry[:plan]) if entry[:plan]
      if entry[:plan] == :no_source
        trip.update_columns(trip_source_id: nil)
      elsif entry[:plan] == :no_identifier
        trip.update_columns(source_identifier: nil)
      end
      if entry[:description]
        ActionText::RichText.insert!({ id:, record_type: 'Trip', record_id: id, name: 'description',
                                      body: entry[:description] }.merge(remaining_stamps))
      end
      state = entry[:show]
      trip.update_columns(path: nil) if entry[:missing] || %i[nil_path no_stats stats future_import future_plain
                                                              repeat].include?(state)
      trip.update_columns(path: 'LINESTRING EMPTY') if state == :empty_path
      trip.update_columns(distance: nil) if state == :nil_distance
      trip.update_columns(distance: 0) if state == :zero_distance
      trip.update_columns(visited_countries: []) if state == :empty_countries
      trip.update_columns(visited_countries: {}) if state == :hash_countries
      if %i[future_import future_plain].include?(state) || %i[future future_stats].include?(entry[:plan])
        trip.update_columns(started_at: now + 2.days, ended_at: now + 3.days, path: nil,
                            source_identifier: state == :future_plain ? nil : 'Future plan')
      end
      if %i[stats future_import].include?(state) || entry[:plan] == :future_stats
        Point.insert!({ id:, user_id: user.id, timestamp: trip.reload.started_at.to_i + 600,
                        lonlat: 'POINT(12.3712 51.3391)' }.merge(remaining_stamps))
      end
      trip.update_columns(path: nil) if entry[:plan] && entry[:plan] != :toggle
      if entry[:action] == :recalculate
        trip.update_columns(last_recalculated_at: entry[:age] && now - entry[:age].seconds)
      end
      if entry[:note] || %i[note_update note_destroy].include?(entry[:action])
        note_trip = entry[:foreign] ? remaining_trip(remaining_user(user.id + 100_000), id + 1) : trip
        remaining_note(note_trip.user, note_trip, id, entry[:action] == :show ? entry[:body] : 'Before')
      end
      return unless entry[:graph]

      Point.insert!({ id:, user_id: user.id, timestamp: now.to_i,
                      lonlat: 'POINT(12.3712 51.3391)' }.merge(remaining_stamps))
      SharedLink.insert!({ id: format('a8a80000-0000-4000-8000-%012d', id), user_id: user.id,
                          resource_type: 0, resource_id: id, name: 'Synthetic link',
                          settings: {} }.merge(remaining_stamps))
      SharedLink.insert!({ id: format('a8a80000-0000-4000-8001-%012d', id), user_id: user.id,
                          resource_type: 1, resource_id: id, name: 'Other resource',
                          settings: {} }.merge(remaining_stamps))
      Export.insert!({ id:, user_id: user.id, name: 'Unrelated export', status: 0, file_type: 0, file_format: 0 }
                      .merge(remaining_stamps))
      RouteVideo.insert!({ id:, user_id: user.id, name: 'Unrelated video', status: 1,
                           settings: {} }.merge(remaining_stamps))
      Poster.insert!({ id:, user_id: user.id, name: 'Unrelated poster', status: 0,
                       settings: {} }.merge(remaining_stamps))
    end

    def remaining_target(entry, id)
      action = entry[:action]
      accept = entry.fetch(:accept, action.to_s.start_with?('note_') ? 'text/vnd.turbo-stream.html' : 'text/html')
      case action
      when :new then [:get, '/trips/new', {}, accept]
      when :index then [:get, '/trips', {}, accept]
      when :edit then [:get, "/trips/#{id}/edit", {}, accept]
      when :show then [:get, "/trips/#{id}", {}, accept]
      when :create then [:post, '/trips', { trip: entry[:attrs] }, accept]
      when :update then [:patch, "/trips/#{id}", { trip: entry[:attrs] }, accept]
      when :destroy then [:delete, "/trips/#{id}", {}, accept]
      when :recalculate then [:post, "/trips/#{id}/recalculate", {}, accept]
      when :export then [:post, "/trips/#{id}/export?file_format=#{entry[:format]}", {}, accept]
      when :note_create
        [:post, "/trips/#{id}/notes", { note: { date: entry.fetch(:date, '2026-10-03'), body: entry[:body] } }, accept]
      when :note_update
        [:patch, "/trips/#{id}/notes/#{id}", { note: { date: '1900-01-01', body: entry[:body] } }, accept]
      when :note_destroy then [:delete, "/trips/#{id}/notes/#{id}", {}, accept]
      end
    end

    def remaining_fault(entry)
      if entry[:fault]
        target = if entry[:owner] == :oban
                   allow(JobOutbox).to(receive(:insert_all))
                 else
                   allow_any_instance_of(Sidekiq::Client).to(receive(:push))
                 end
        target.and_wrap_original do |original, *args, **kwargs|
          raise 'synthetic queue failure' if entry[:fault] == :enqueue

          result = original.call(*args, **kwargs)
          ActiveRecord::Base.connection.execute('SELECT a8_remaining_missing_column FROM trips')
          result
        end
      end
      return unless entry[:race]

      calls = 0
      allow(Note).to receive(:for_date).and_wrap_original do |original, *args|
        calls += 1
        calls == 1 ? Note.none : original.call(*args)
      end
      allow_any_instance_of(Note).to receive(:save).and_wrap_original do |original, *args|
        raise ActiveRecord::RecordNotUnique, 'notes unique index' if original.receiver.new_record?

        original.call(*args)
      end
    end

    def remaining_assert(entry, user, id, before, queue, error)
      name = entry[:name]
      if entry[:error]
        expect(error&.class&.name).to eq(entry[:error]),
                                      "#{name}: expected #{entry[:error]}, got #{error&.class&.name || response.status}"
      else
        expect(error).to be_nil, name
        expect(response.status).to eq(entry.fetch(:expected, 200)), name
      end
      trip = Trip.find_by(id: id)
      if entry[:foreign]
        expect(remaining_graph(user, id)).to eq(before), name
        expect(queue.values_at(:jobs, :sidekiq, :outbox)).to all(be_empty)
      elsif entry[:fault]
        expect(remaining_graph(user, id)).to eq(before), name
        expect(queue[:outbox]).to be_empty
        expect(queue[:sidekiq].length).to eq(entry[:owner] == :sidekiq && entry[:fault] == :sql ? 1 : 0), name
      elsif entry[:action] == :create
        created = user.trips.find_by(id: id + 10)
        if entry[:expected] == 302
          expect(created.name).to eq(entry[:attrs][:name]), name
          expect(created.demo).to be(false)
          expect(queue[:sidekiq].length + queue[:outbox].length).to eq(1), name
          expected_start = case entry[:name]
                           when /dst_gap/ then utc('2026-03-29T01:30:00Z')
                           when /dst_fold/ then utc('2026-10-25T00:30:00Z')
                           else utc('2026-10-03T07:00:00Z')
                           end
          expect(created.started_at.utc).to eq(expected_start), name
        else
          expect(created).to be_nil, name
          expect(queue.values_at(:jobs, :sidekiq, :outbox)).to all(be_empty)
        end
      elsif entry[:action] == :update && !entry[:error] && entry[:expected] == 303
        expect(trip.demo).to be(false), name
        calculates = entry[:attrs].key?(:started_at) && !entry[:demo]
        expect(queue[:sidekiq].length + queue[:outbox].length).to eq(calculates ? 1 : 0), name
      elsif entry[:action] == :recalculate
        eligible = entry[:age].nil? || entry[:age] > 60
        expect(trip.last_recalculated_at).to eq(eligible ? now : now - entry[:age].seconds), name
        expect(trip.updated_at).to eq(now - 2.hours), name
        expect(queue[:sidekiq].length + queue[:outbox].length).to eq(eligible ? 1 : 0), name
      elsif entry[:action] == :destroy && !entry[:foreign]
        expect(trip).to be_nil
        [Note, ActionText::RichText, PlannedDay, PlannedStop, PlannedDayNote, PlannedReservation,
         PlannedAccommodation, PlannedTraveller, PlannedUnplannedPlace].each do |model|
          scope = if model == ActionText::RichText
                    model.where(record_type: 'Trip',
                                record_id: id)
                  else
                    model.where(id: id...id + 20)
                  end
          expect(scope).to be_empty, "#{name}: #{model.name}"
        end
        expect([Point, Export, RouteVideo, Poster, TripSource].map { _1.where(id: id).count }).to eq([1, 1, 1, 1, 1])
        expect(SharedLink.where(resource_id: id).pluck(:resource_type)).to eq(['track'])
      elsif entry[:action] == :export && entry[:format] != 'csv'
        export = user.exports.order(:id).last
        parameter = { 'Auwald' => 'auwald', 'Über Auwald' => 'uber-auwald', '!!!' => id.to_s, '' => id.to_s }
        expect(export.name).to eq("trip_#{parameter.fetch(entry.fetch(:title, 'Auwald'))}_2026-10-03.#{entry[:format]}")
        expect([export.start_at, export.end_at]).to eq([trip.started_at, trip.ended_at])
      elsif entry[:action] == :show
        future_import = trip.source_imported? && trip.started_at > now
        needed = !future_import && (trip.path.blank? || trip.distance.blank? || trip.visited_countries.blank?)
        count = if needed
                  entry[:show] == :repeat && entry[:owner] == :sidekiq ? 2 : 1
                else
                  0
                end
        expect(queue[:sidekiq].length + queue[:outbox].length).to eq(count), name
      elsif %i[note_create note_update].include?(entry[:action]) && !entry[:error] && !entry[:foreign]
        date = entry.fetch(:date, '2026-10-03')
        valid = entry[:body].present? && entry[:body].length <= Note::MAX_BODY_LENGTH &&
                %w[2026-10-03 2026-10-04].include?(date)
        note = trip.notes.for_date('2026-10-03').first
        if valid && date == '2026-10-03'
          expect(note.body).to eq(entry[:body]), name
          expect(note.noted_at.utc).to eq(utc('2026-10-03T12:00:00Z'))
          expect(trip.notes.count).to eq(1)
        elsif !valid && entry[:action] == :note_update
          expect(note.body).to eq('Before'), name
        elsif !valid
          expect(trip.notes).to be_empty, name
        end
      end
      queue[:outbox].select { _1['command_type'] == 'trips.calculate' }.each do |row|
        expect(row['command_version']).to eq(1)
        expect(row['payload']).to eq('trip_id' => row['aggregate_id'], 'distance_unit' => 'km')
        expect(row['dedupe_key']).to eq(row['aggregate_id'].to_s)
        expect(row['metadata']).to eq('producer' => 'Trip#enqueue_calculation_jobs')
        expect(row['scheduled_at']).to eq(now.iso8601(6))
      end
      return if error

      html = remaining_html(response.body)
      if entry[:body] && !entry[:foreign] && (entry[:action] == :show || html.include?('<textarea'))
        raw = html.scan(%r{<textarea\b[^>]*>(.*?)</textarea>}m).flatten.first
        expect(raw).to eq(ERB::Util.html_escape(entry[:body])), name
        parsed = Nokogiri::HTML5.fragment("<textarea>#{raw}</textarea>").at_css('textarea').content
        expect(parsed).to eq(entry[:body].delete_prefix("\n")), name
      end
      return unless entry[:plan]

      doc = Nokogiri::HTML5.fragment(html)
      if entry[:action] == :edit
        managed = entry[:plan] != :stopped && entry[:plan] != :no_identifier
        expect(doc.at_css('input[name="trip[name]"]').key?('readonly')).to eq(managed), name
      elsif entry[:action] == :show
        section = doc.at_css('section[aria-labelledby="trip-plan-title"]')
        expect(section).not_to be_nil, name
        expect(section.text.include?('Source detail')).to eq(entry[:plan] != :synced), name
        stops = trip.plan_geojson[:features].select { _1[:properties][:kind] == 'stop' }
        expect(stops.map { _1[:properties][:number] }).to eq([2, 3, 4])
        expect(stops.first[:geometry][:coordinates]).to eq([12.3712, 51.3391])
      end
    end

    it 'writes A8 remaining trip responses and effects' do
      expect(Rails.application.secret_key_base).to eq(secret)
      allow(Trips::CalculateAllJob).to receive(:queue_adapter).and_return(ActiveJob::QueueAdapters::SidekiqAdapter.new)
      responses = []
      effects = []
      travel_to now do
        allow(ExceptionReporter).to receive(:call)
        remaining_scenarios.each_with_index do |entry, index|
          id = 895_000 + index * 20
          user = remaining_user(8950 + index)
          job_owner!('command:trips.calculate', entry.fetch(:owner, :sidekiq))
          job_owner!('command:exports.points', entry.fetch(:owner, :sidekiq))
          remaining_setup(user, id, entry)
          %w[trips notes exports action_text_rich_texts].each do |table|
            ActiveRecord::Base.connection.execute(
              "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 10}, false)"
            )
          end
          clear_enqueued_jobs
          Sidekiq::ActiveJob::Wrapper.clear
          before = remaining_graph(user, id)
          method, path, params, accept = remaining_target(entry, id)
          error = nil
          commands = []
          RSpec::Mocks.with_temporary_scope do
            remaining_fault(entry)
            allow(JobCommands).to receive(:produce).and_wrap_original do |original, type, payload, **options|
              command = { type:, payload:, **options }
              commands << command
              begin
                command[:result] = original.call(type, payload, **options)
              rescue StandardError => e
                command[:error] = e.class.name
                raise
              end
            end
            begin
              ActiveRecord::Base.transaction(requires_new: true) do
                remaining_request(user, method, path, params, accept)
                remaining_request(user, method, path, params, accept) if entry[:show] == :repeat
              end
            rescue StandardError => e
              error = e
            end
          end
          queue = remaining_queue(id)
          queue[:commands] = commands
          remaining_assert(entry, user, id, before, queue, error)
          request = { method: method.to_s.upcase, path:, params:, accept:, owner: entry.fetch(:owner, :sidekiq),
                      fault: entry[:fault], race: entry[:race] }
          responses << remaining_response(entry[:name], error).merge(request:)
          effects << { name: entry[:name], request:, before:, after: remaining_graph(user, id), queue: }
          next unless !error && accept == 'text/html' && entry[:action].to_s.start_with?('note_')

          follow_redirect!
          expect(response.status).to eq(200), entry[:name]
          responses << remaining_response("#{entry[:name]}_follow")
        end
        write_json('responses.json', { now: now.iso8601, responses: })
        write_json('effects.json', { now: now.iso8601, effects: })
        user = remaining_user(98_981)
        foreign = remaining_user(98_982)
        trip = remaining_trip(user, 9_898_101)
        other = remaining_trip(foreign, 9_898_201)
        remaining_plan(foreign, trip, trip.id, :active)
        other.planned_reservations.create!(planned_day_id: trip.planned_days.first.id,
                                           title: 'Foreign reservation', **remaining_stamps)
        remaining_request(user, :get, "/trips/#{trip.id}", {}, 'text/html')
        expect(response.status).to eq(200)
        expect(response.body).to include('Foreign reservation', 'trek.example.invalid')
        reservation = other.planned_reservations.first
        remaining_request(user, :delete, "/trips/#{trip.id}", {}, 'text/html')
        expect(response.status).to eq(303)
        expect(reservation.reload.planned_day_id).to be_nil
      end
    end
  end

  context 'A8 route videos' do
    let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }
    let(:a8_recipe) do
      { 'theme' => 'dark', 'format' => 'landscape', 'duration_sec' => '15', 'camera_mode' => 'follow',
        'follow_zoom' => '14', 'track_color' => '#aa33cc', 'track_width' => '4', 'hud_scale' => '1',
        'units' => 'km', 'watermark' => 'true', 'visualization_mode' => 'route', 'fog_opacity' => '0.4',
        'fog_color' => '#ffffff', 'show_marker' => 'true', 'show_route' => 'true', 'source' => 'trip',
        'start_at' => '2026-10-03T08:00:00Z', 'end_at' => '2026-10-03T09:00:00Z' }
    end

    def a8_video_user(id)
      user = create(:user, id:, email: "a8vv-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                          plan: User.plans[:pro], api_key: "a8vv-k-#{id}", theme: 'dark')
      user.reload
    end

    def a8_blob(id, type: 'video/mp4', size: nil)
      bytes = Rails.root.join('spec/fixtures/files/route_video.mp4').binread
      blob = ActiveStorage::Blob.create!(id:, key: "a8vv-synthetic-#{id}", filename: 'synthetic-route.mp4',
                                         content_type: type, byte_size: size || bytes.bytesize,
                                         checksum: Digest::MD5.base64digest(bytes), service_name: 'test',
                                         metadata: { identified: true, analyzed: true }, created_at: now - 1.hour)
      blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
      blob
    end

    def a8_video(user, id, blob: nil, created_at: now - 2.hours, status: :stored)
      video = RouteVideo.create!(id:, user:, name: 'Synthetic route', settings: a8_recipe,
                                 status:, created_at:, updated_at: created_at,
                                 expired_at: status == :expired ? now - 1.hour : nil)
      if blob
        ActiveStorage::Attachment.create!(id:, name: 'file', record: video, blob:, created_at:)
        video.update_columns(updated_at: created_at)
      end
      video.reload
    end

    def a8_video_graph(user)
      video_ids = user.route_videos.order(:id).pluck(:id)
      first_blob = user.id < 8880 ? 886_000 + (user.id - 8860) * 10 : 888_000 + (user.id - 8880) * 10
      blob_ids = ActiveStorage::Blob.where(id: first_blob...first_blob + 10).order(:id).pluck(:id)
      { user: { id: user.id, email: user.email, settings: user.settings, plan: User.plans[user.plan],
                theme: user.theme, active_until: user.active_until.utc.iso8601(6) },
        route_videos: RouteVideo.where(id: video_ids).order(:id).map { a8_video_attributes(_1) },
        active_storage_attachments: ActiveStorage::Attachment.where(blob_id: blob_ids).order(:id).map do
          a8_video_attributes(_1)
        end,
        active_storage_blobs: ActiveStorage::Blob.where(id: blob_ids).order(:id).map { a8_video_attributes(_1) } }
    end

    def a8_video_attributes(row)
      attrs = row.attributes.transform_values { _1.respond_to?(:utc) ? _1.utc.iso8601(6) : _1 }
      attrs['status'] = RouteVideo.statuses[row.status] if row.is_a?(RouteVideo)
      attrs
    end

    def a8_video_card(video)
      ApplicationController.render(partial: 'route_videos/route_video', locals: { route_video: video })
    end

    def a8_video_record(name, user, before, request, body: response.body, status: response.status)
      target = Rails.root.join('app-phoenix/test/fixtures/a8vv/videos')
      FileUtils.mkdir_p(target)
      body = body.gsub(%r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/]+/}, '\1BLOB_SIGNED_ID/')
      File.write(target.join("#{name}.html"), body)
      data = { now: now.iso8601, request:, before:, after: a8_video_graph(user), status:,
               content_type: request[:method] ? response.media_type : 'text/html',
               location: request[:method] ? response.location : nil,
               flash: request[:method] ? flash.to_hash : {},
               headers: if request[:method]
                          response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control',
                                                 'X-Frame-Options', 'Referrer-Policy', 'X-Content-Type-Options')
                        else
                          {}
                        end,
               jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue] } } }
      File.write(target.join("#{name}.json"),
                 "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n")
    end

    def a8_video_request(user, method, path, params: {}, accept: 'text/vnd.turbo-stream.html')
      reset!
      sign_in user
      get '/settings/visits'
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      clear_enqueued_jobs
      public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    end

    it 'writes A8 video responses and effects' do
      travel_to now do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(10)
        allow(ExceptionReporter).to receive(:call)
        cases = %w[all_recipe_keys untitled unknown_recipe unicode_recipe_65 exact_ceiling wrong_mime
                   over_ceiling invalid_signature pre_attach_error post_commit_cap_error cap_one cap_zero]
        cases.each_with_index do |name, index|
          user = a8_video_user(8860 + index)
          id = 886_000 + index * 10
          allow(DawarichSettings).to receive(:video_max_per_user).and_return(name == 'cap_one' ? 1 : 0)
          mime = name == 'wrong_mime' ? 'text/plain' : 'video/mp4'
          size = { 'exact_ceiling' => 250 * 1024 * 1024, 'over_ceiling' => 250 * 1024 * 1024 + 1 }[name]
          blob = a8_blob(id, type: mime, size:)
          old = nil
          if %w[cap_one cap_zero post_commit_cap_error].include?(name)
            old = a8_video(user, id + 1, blob: a8_blob(id + 1))
            allow(DawarichSettings).to receive(:video_max_per_user).and_return(name == 'cap_zero' ? 0 : 1)
          end
          %w[route_videos active_storage_attachments].each do |table|
            ActiveRecord::Base.connection.execute(
              "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 2}, false)"
            )
          end
          recipe = a8_recipe.dup
          recipe['unknown'] = 'discard' if name == 'unknown_recipe'
          unicode = "#{'a' * 61}é👩‍💻end"
          recipe['source'] = unicode if name == 'unicode_recipe_65'
          params = { route_video: { name: name == 'untitled' ? '' : 'Saved route', file: blob.signed_id,
                                   settings: recipe } }
          params[:route_video][:file] = 'invalid-signed-id' if name == 'invalid_signature'
          before = a8_video_graph(user)
          RSpec::Mocks.with_temporary_scope do
            if name == 'pre_attach_error'
              allow_any_instance_of(RouteVideo).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(RouteVideo.new))
            elsif name == 'post_commit_cap_error'
              allow_any_instance_of(RouteVideo).to receive(:update!).and_raise('synthetic expiry status failure')
            end
            a8_video_request(user, :post, '/route_videos', params:)
          end
          rejected = %w[wrong_mime over_ceiling invalid_signature pre_attach_error post_commit_cap_error].include?(name)
          expect(response.status).to eq(rejected ? 422 : 200), name
          saved = user.route_videos.find_by(id: id + 2)
          if %w[wrong_mime over_ceiling invalid_signature pre_attach_error].include?(name)
            expect(saved).to be_nil, name
            expect(blob.attachments).to be_empty
            if name == 'invalid_signature'
              expect(enqueued_jobs).to be_empty
            else
              expect(enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.size).to eq(1)
            end
          else
            expect(saved).to be_present, name
            expect(saved.file.blob.id).to eq(blob.id)
            expect(saved.name).to eq(name == 'untitled' ? I18n.t('controllers.route_videos.untitled') : 'Saved route')
            wanted = a8_recipe.merge(name == 'unicode_recipe_65' ? { 'source' => "#{'a' * 61}é👩" } : {})
            expect(saved.settings).to eq(wanted), name
            if old
              expect(old.reload.status).to eq(name == 'cap_one' ? 'expired' : 'stored')
              expect(old.file.attached?).to eq(name == 'cap_zero')
              expect(old.updated_at).to eq(name == 'cap_zero' ? now - 2.hours : now)
              expect(old.expired_at).to eq(name == 'cap_one' ? now : nil)
            end
            streams = Nokogiri::HTML5.fragment(response.body).css('turbo-stream').map { [_1['action'], _1['target']] }
            wanted_streams = if name == 'post_commit_cap_error'
                               [%w[append flash-messages]]
                             else
                               [%w[prepend route-video-gallery-list],
                                *(name == 'cap_one' ? [['replace', "route_video_#{old.id}"]] : []),
                                %w[append flash-messages]]
                             end
            expect(streams).to eq(wanted_streams)
          end
          reference = name == 'invalid_signature' ? 'INVALID_SIGNED_ID' : 'BLOB_SIGNED_ID'
          request = { method: 'POST', path: '/route_videos', accept: 'text/vnd.turbo-stream.html',
                      params: params.deep_merge(route_video: { file: reference }),
                      blob_id: blob.id,
                      fault: %w[pre_attach_error post_commit_cap_error].include?(name) ? name : nil }
          a8_video_record(name, user, before, request)
        end

        %w[playable_card expired_card stored_without_file destroy_html destroy_stream shared_blob
           aged_boundary].each_with_index do |name, index|
          user = a8_video_user(8880 + index)
          id = 888_000 + index * 10
          blob = a8_blob(id) unless name == 'stored_without_file'
          video = a8_video(user, id, blob:, status: name == 'expired_card' ? :expired : :stored)
          before = a8_video_graph(user)
          clear_enqueued_jobs
          if name.start_with?('destroy_')
            accept = name == 'destroy_html' ? 'text/html' : 'text/vnd.turbo-stream.html'
            a8_video_request(user, :delete, "/route_videos/#{id}", accept:)
            expect(response.status).to eq(name == 'destroy_html' ? 303 : 200)
            expect(RouteVideo.exists?(id)).to be(false)
            expect(ActiveStorage::Attachment.where(record_type: 'RouteVideo', record_id: id)).to be_empty
            expect(enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.size).to eq(1)
            if name == 'destroy_html'
              expect(response).to redirect_to('/map/v2')
            else
              expect(response.body).to eq(
                "<turbo-stream action=\"remove\" target=\"route_video_#{id}\"></turbo-stream>"
              )
            end
            a8_video_record(name, user, before, { method: 'DELETE', path: "/route_videos/#{id}", accept: })
          elsif name == 'shared_blob'
            second = a8_video(user, id + 1, blob:)
            before = a8_video_graph(user)
            video.expire!
            expect(video.reload.status).to eq('expired')
            expect(video.file.attached?).to be(false)
            expect(video.settings).to eq(a8_recipe)
            expect(video.updated_at).to eq(now)
            expect(video.expired_at).to eq(now)
            purge_args = enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.map { _1[:args] }
            expect(purge_args).to eq([[{ '_aj_globalid' => "gid://dawarich/ActiveStorage::Blob/#{blob.id}" }]])
            queued = enqueued_jobs.map { { job: _1[:job].name, args: _1[:args] } }
            perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
            expect(second.reload.file.attached?).to be(true)
            expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
            expect(blob.service.exist?(blob.key)).to be(true)
            a8_video_record(name, user, before, { operation: 'expire_and_purge', video_id: id, queued: },
                            body: a8_video_card(video), status: 200)
          elsif name == 'aged_boundary'
            video.update_columns(created_at: now - 30.days - 1.second)
            boundary = a8_video(user, id + 1, blob: a8_blob(id + 1), created_at: now - 30.days)
            allow(DawarichSettings).to receive(:video_retention_days).and_return(30)
            allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
            before = a8_video_graph(user)
            RouteVideos::PurgeJob.perform_now
            expect(video.reload.status).to eq('expired')
            expect(video.file.attached?).to be(false)
            expect(boundary.reload.status).to eq('stored')
            expect(boundary.file.attached?).to be(true)
            a8_video_record(name, user, before, { operation: 'retention', days: 30, cap: 0 },
                            body: a8_video_card(video), status: 200)
          else
            body = a8_video_card(video)
            if name == 'playable_card'
              expect(Nokogiri::HTML5.fragment(body).at_css('video')['controls']).not_to be_nil
              expect(body).to include('disposition=attachment')
            else
              expect(Nokogiri::HTML5.fragment(body).css('video')).to be_empty
              expect(body).to include('video-studio#restoreSettings')
            end
            a8_video_record(name, user, before, { operation: 'card', video_id: id }, body:, status: 200)
          end
        end
      end
    end

    %w[blank_name_cap blank_name_cron].each_with_index do |name, index|
      it "writes A8 review #{name} from Rails" do
        travel_to now do
          user = a8_video_user(8887 + index)
          id = 888_070 + index * 10
          video = a8_video(user, id + 1, blob: a8_blob(id + 1), created_at: now - 31.days)
          video.update_columns(name: '')
          allow(DawarichSettings).to receive(:video_retention_days).and_return(30)
          allow(DawarichSettings).to receive(:video_max_per_user).and_return(name == 'blank_name_cap' ? 1 : 0)
          allow(ExceptionReporter).to receive(:call)
          if name == 'blank_name_cap'
            blob = a8_blob(id)
            %w[route_videos active_storage_attachments].each do |table|
              ActiveRecord::Base.connection.execute(
                "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 2}, false)"
              )
            end
            before = a8_video_graph(user)
            params = { route_video: { name: 'Saved route', file: blob.signed_id, settings: a8_recipe } }
            a8_video_request(user, :post, '/route_videos', params:)
            expect(response.status).to eq(422)
            expect(user.route_videos.count).to eq(2)
            expect(video.reload.status).to eq('stored')
            expect(video.file.attached?).to be(false)
            expect(video.updated_at).to eq(now)
            expect(video.expired_at).to be_nil
            request = { method: 'POST', path: '/route_videos', accept: 'text/vnd.turbo-stream.html',
                        params: params.deep_merge(route_video: { file: 'BLOB_SIGNED_ID' }), blob_id: blob.id }
            a8_video_record(name, user, before, request)
          else
            before = a8_video_graph(user)
            clear_enqueued_jobs
            expect { RouteVideos::PurgeJob.perform_now }.to raise_error(ActiveRecord::RecordInvalid, /Name/)
            expect(a8_video_graph(user)).to eq(before)
            a8_video_record(name, user, before, { operation: 'retention_failure', days: 30, cap: 0,
                                                error: 'ActiveRecord::RecordInvalid' }, body: '', status: 422)
          end
        end
      end
    end

    it 'writes A8 attachment identification boundaries' do
      travel_to now do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
        %w[unidentified preidentified shared_preidentified].each_with_index do |name, index|
          user = a8_video_user(8895 + index)
          id = 888_150 + index * 10
          blob = a8_blob(id)
          metadata = name == 'unidentified' ? {} : { identified: true }
          metadata[:analyzed] = true if name == 'shared_preidentified'
          blob.update!(metadata:)
          other = a8_video(user, id + 1, blob:) if name == 'shared_preidentified'
          %w[route_videos active_storage_attachments].each do |table|
            ActiveRecord::Base.connection.execute(
              "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 2}, false)"
            )
          end
          before = a8_video_graph(user)
          params = { route_video: { name: 'Metadata route', file: blob.signed_id, settings: a8_recipe } }
          a8_video_request(user, :post, '/route_videos', params:)
          expect(response.status).to eq(200), name
          saved = user.route_videos.find_by!(name: 'Metadata route')
          expect(saved.file.blob.id).to eq(id)
          expect(blob.reload.identified?).to be(true)
          if name == 'shared_preidentified'
            expect(blob.attachments.count).to eq(2)
            expect(other.reload.file.blob.id).to eq(id)
            expect(enqueued_jobs).to be_empty
          else
            expect(enqueued_jobs.map { _1[:job] }).to eq([ActiveStorage::AnalyzeJob])
          end
          request = { method: 'POST', path: '/route_videos', accept: 'text/vnd.turbo-stream.html',
                      params: params.deep_merge(route_video: { file: 'BLOB_SIGNED_ID' }), blob_id: id }
          a8_video_record("metadata_#{name}", user, before, request)
        end
      end
    end
  end

  def user_settings
    {
      9801 => { 'timezone' => 'Europe/Berlin', 'airtrail_url' => ' ' },
      9802 => { 'timezone' => 'America/New_York', 'maps' => { 'distance_unit' => 'mi' },
                'maps_maplibre_style' => 'dark', 'airtrail_url' => 'https://airtrail.example',
                'meters_between_routes' => '750', 'minutes_between_routes' => 90 },
      9803 => { 'timezone' => 'UTC' },
      9804 => { 'timezone' => 'Europe/Berlin' },
      9805 => { 'timezone' => 'Europe/Berlin' },
      9899 => { 'timezone' => 'Europe/Berlin' }
    }
  end

  def loop_path
    [[12.373468123456789, 51.33970012345678], [12.38, 51.345], [12.391234567890123, 51.34987654321098],
     [12.4, 51.34000000000001], [12.373468123456789, 51.33970012345678]]
  end

  def short_path = [[12.3712, 51.3391], [12.3801, 51.3422]]

  def line(lon, lat, count) = (0...count).map { |i| [lon + (i * 0.001), lat + (i * 0.0005)] }

  def trip(id, user_id, name, started, ended, opts = {})
    { id:, user_id:, name:, started_at: started, ended_at: ended, distance: opts[:distance],
      visited_countries: opts.fetch(:countries, []), path: opts[:path], recalculated_offset: opts[:recalculated] }
  end

  def many_trips
    (1..14).map do |n|
      trip(980_500 + n, 9805, format('Many %02d', n), (Time.utc(2024, 1, 1, 8) + n.days).iso8601(6),
           (Time.utc(2024, 1, 1, 18) + n.days).iso8601(6), distance: n.even? ? n * 1000 : nil,
           countries: n.even? ? ['Germany'] : [], path: n.even? ? line(12.3 + (n * 0.01), 51.3, 2) : nil)
    end
  end

  def trips
    [
      trip(980_101, 9801, 'Leipzig loop', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 12_345, countries: ['Germany'], path: loop_path, recalculated: 30),
      trip(980_102, 9801, 'Grenzgang <b>&</b> "Saale"', '2026-01-31T09:00:00.000000Z',
           '2026-02-02T07:00:00.000000Z', distance: 999_500, countries: %w[Germany France],
           path: line(12.35, 51.33, 3), recalculated: 3600),
      trip(980_103, 9801, 'No points', '2025-12-01T08:00:00.000000Z', '2025-12-01T18:00:00.000000Z', distance: 0),
      trip(980_104, 9801, 'Calculating', '2025-11-01T08:00:00.000000Z', '2025-11-02T08:00:00.000001Z',
           countries: {}),
      trip(980_105, 9801, 'Countryless', '2025-10-01T08:00:00.000000Z', '2025-10-01T09:30:00.000000Z',
           distance: 500, path: short_path),
      trip(980_106, 9801, 'Short hop', '2025-09-01T08:00:00.000000Z', '2025-09-01T09:00:00.000000Z',
           distance: 1499, countries: ['Germany'], path: short_path),
      trip(980_201, 9802, 'Auenwald walk', '2026-04-20T13:00:00.000000Z', '2026-04-21T02:30:00.000000Z',
           distance: 16_093, countries: ['United States'], path: line(12.33, 51.35, 4), recalculated: 3600),
      trip(980_301, 9803, 'Midnight run', '2026-06-01T22:00:00.000000Z', '2026-06-03T01:00:00.000000Z',
           distance: 800, countries: ['Germany'], path: line(12.36, 51.32, 2)),
      trip(980_302, 9803, 'Auwald notes', '2026-07-04T08:00:00.000000Z', '2026-07-05T18:00:00.000000Z',
           distance: 2500, countries: ['Germany'], path: short_path),
      *many_trips,
      trip(989_901, 9899, 'Foreign trip', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 1000, countries: ['Germany'], path: loop_path)
    ]
  end

  def point(id, user_id, time, lon, lat, opts = {})
    { id:, user_id:, timestamp: utc(time).to_i, lon:, lat:, tracker_id: opts[:tracker], source_id: opts[:source],
      anomaly: opts[:anomaly] }
  end

  def points
    [
      point(9_810_001, 9801, '2026-05-09T07:00:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_810_002, 9801, '2026-05-09T07:10:00Z', 12.375, 51.3395, tracker: 'phone'),
      point(9_810_003, 9801, '2026-05-09T07:20:00Z', 12.381, 51.341, tracker: 'phone'),
      point(9_810_004, 9801, '2026-05-09T07:30:00Z', 12.389, 51.344, tracker: 'phone'),
      point(9_810_005, 9801, '2026-05-10T06:00:00Z', 12.3712, 51.3391, tracker: 'phone'),
      point(9_810_006, 9801, '2026-05-10T06:05:00Z', 12.379, 51.342, source: 98_001),
      point(9_810_007, 9801, '2026-05-10T06:15:00Z', 12.376, 51.3405, tracker: 'phone'),
      point(9_810_008, 9801, '2026-05-10T06:20:00Z', 12.383, 51.345, source: 98_001),
      point(9_810_009, 9801, '2026-05-10T06:30:00Z', 12.3801, 51.3422, tracker: 'phone'),
      point(9_810_010, 9801, '2026-05-10T08:00:00Z', 12.39, 51.36, tracker: 'phone', anomaly: true),
      point(9_810_011, 9801, '2026-05-10T09:00:00Z', 12.39, 51.35, tracker: 'phone'),
      point(9_810_012, 9801, '2026-05-10T09:10:00Z', 12.395, 51.353, tracker: 'phone'),
      point(9_810_013, 9801, '2026-05-10T12:00:00Z', 12.4, 51.33, source: 98_001),
      point(9_810_014, 9801, '2026-05-10T12:10:00Z', 12.41, 51.33, source: 98_001),
      point(9_810_015, 9801, '2026-05-10T15:00:00Z', 12.42, 51.325, source: 98_002),
      point(9_810_016, 9801, '2026-05-10T22:30:00Z', 12.37, 51.34, tracker: 'phone'),
      point(9_810_017, 9801, '2026-05-10T22:35:00Z', 12.3701, 51.3403, tracker: 'phone'),
      point(9_810_101, 9801, '2026-02-01T10:00:00Z', 12.35, 51.33, tracker: 'phone'),
      point(9_810_102, 9801, '2026-02-01T11:00:00Z', 12.35, 51.34, tracker: 'phone'),
      point(9_820_001, 9802, '2026-04-20T14:00:00Z', 12.33, 51.35, tracker: 'pixel'),
      point(9_820_002, 9802, '2026-04-20T15:00:00Z', 12.33, 51.37, tracker: 'pixel'),
      point(9_830_001, 9803, '2026-06-01T22:10:00Z', 12.36, 51.32),
      point(9_830_002, 9803, '2026-06-01T22:12:00Z', 12.3601, 51.3201),
      point(9_830_003, 9803, '2026-06-03T00:10:00Z', 12.36, 51.32),
      point(9_830_004, 9803, '2026-06-03T00:40:00Z', 12.36, 51.335),
      point(9_890_001, 9899, '2026-05-09T07:05:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_890_002, 9899, '2026-05-10T06:10:00Z', 12.379, 51.342, tracker: 'phone')
    ]
  end

  def countries
    [{ name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU' }, { name: 'France', iso_a2: 'FR', iso_a3: 'FRA' },
     { name: 'United States', iso_a2: 'US', iso_a3: 'USA' }]
  end

  def sources = [{ id: 98_001, tracker_id: 'watch' }, { id: 98_002, tracker_id: nil }]

  def notes
    [{ id: 9_811, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-10T12:00:00Z',
       body: "Morgenkaffee <b>am</b> See\nthen the Auensee" },
     { id: 9_812, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-20T12:00:00Z', body: 'Outside the trip' },
     { id: 9_833, trip_id: 980_302, user_id: 9803, noted_at: '2026-07-05T12:00:00Z',
       body: %(Picknick am "Auensee" & 'Rosental') },
     { id: 9_891, trip_id: 989_901, user_id: 9899, noted_at: '2026-05-10T12:00:00Z', body: 'Foreign note' }]
  end

  def described
    '<h1>Leipzig &amp; the Auwald</h1><div>From the <strong>Rosental</strong> <em>along</em> the ' \
      '<del>Elster</del> Pleiße<br>two&nbsp;&nbsp;spaces, "quotes" and 3 &lt; 4 &gt; 2</div>' \
      '<blockquote>Leise rauscht der Fluss</blockquote><ul><li>Rosental<ul><li>Zoo</li></ul></li><li>' \
      '<a href="https://www.leipzig.de/freizeit?x=1&amp;y=2#auwald">Auwald</a></li></ul><ol><li>Auensee</li>' \
      "</ol><pre>12.3712 51.3391\n12.3801 51.3422</pre>"
  end

  def rich_texts = [{ trip_id: 980_302, body: described }]

  def shared_links
    [{ id: 'a8510000-0000-4000-8000-000000000001', resource_type: 0, trip_id: 980_101, user_id: 9801,
       revoked: false, expires_offset: 7.days.to_i },
     { id: 'a8510000-0000-4000-8000-000000000002', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: true, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000003', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: false, expires_offset: -1.day.to_i },
     { id: 'a8510000-0000-4000-8000-000000000004', resource_type: 1, trip_id: 980_102, user_id: 9801,
       revoked: false, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000005', resource_type: 0, trip_id: 989_901, user_id: 9899,
       revoked: false, expires_offset: nil }]
  end

  def posters
    [{ id: 9_831, user_id: 9803, name: 'Leipzig poster', status: 0, created_at: '2026-09-20T10:00:00.000000Z' }]
  end

  def route_videos
    [{ id: 9_832, user_id: 9803, name: 'Run video', status: 1, expired_at: '2026-09-01T18:30:00.000000Z',
       settings: { 'format' => 'landscape' }, created_at: '2026-08-20T10:00:00.000000Z' }]
  end

  def create_users!
    user_settings.map do |id, settings|
      user = create(:user, id:, email: "a8-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(settings).merge('onboarding_completed' => true),
                          api_key: "a8-k-#{id}")
      user.reload
      { id:, email: user.email, settings: user.settings, api_key: user.api_key }
    end
  end

  def insert!
    Country.insert_all(countries.map { |c| c.merge(created_at: now, updated_at: now) })
    PointSource.insert_all(sources.map { |s| s.merge(digest: "a8s1#{s[:id]}", created_at: now, updated_at: now) })
    Trip.insert_all(trips.map do |t|
      t.slice(:id, :user_id, :name, :distance, :visited_countries)
       .merge(started_at: utc(t[:started_at]), ended_at: utc(t[:ended_at]),
              path: t[:path] && "LINESTRING(#{t[:path].map { |x, y| "#{x} #{y}" }.join(', ')})",
              last_recalculated_at: t[:recalculated_offset] && (now - t[:recalculated_offset]),
              created_at: now, updated_at: now)
    end)
    Point.insert_all(points.map do |p|
      p.slice(:id, :user_id, :timestamp, :tracker_id, :source_id, :anomaly)
       .merge(lonlat: "POINT(#{p[:lon]} #{p[:lat]})", created_at: now, updated_at: now)
    end)
    Note.insert_all(notes.map do |n|
      { id: n[:id], attachable_type: 'Trip', attachable_id: n[:trip_id], user_id: n[:user_id], body: n[:body],
        noted_at: utc(n[:noted_at]), created_at: now, updated_at: now }
    end)
    ActionText::RichText.insert_all(rich_texts.map do |r|
      { record_type: 'Trip', record_id: r[:trip_id], name: 'description', body: r[:body], created_at: now,
        updated_at: now }
    end)
    SharedLink.insert_all(shared_links.map do |l|
      { id: l[:id], name: 'Fixture link', resource_type: SharedLink.resource_types.key(l[:resource_type]),
        resource_id: l[:trip_id], user_id: l[:user_id], revoked_at: l[:revoked] ? now - 1.day : nil,
        expires_at: l[:expires_offset] && (now + l[:expires_offset]), settings: {}, created_at: now, updated_at: now }
    end)
    Poster.insert_all(posters.map do |p|
      p.slice(:id, :user_id, :name).merge(status: Poster.statuses.key(p[:status]), settings: {},
                                          created_at: utc(p[:created_at]), updated_at: utc(p[:created_at]))
    end)
    RouteVideo.insert_all(route_videos.map do |v|
      v.slice(:id, :user_id, :name, :settings).merge(status: RouteVideo.statuses.key(v[:status]),
                                                     expired_at: utc(v[:expired_at]), created_at: utc(v[:created_at]),
                                                     updated_at: utc(v[:created_at]))
    end)
  end

  def pages
    [
      ['index_states', 9801, '/trips'], ['index_ny', 9802, '/trips'], ['index_empty', 9804, '/trips'],
      ['index_many_page1', 9805, '/trips'], ['index_many_page2', 9805, '/trips?page=2'],
      ['index_many_page3', 9805, '/trips?page=3'], ['index_many_page0', 9805, '/trips?page=0'],
      ['index_many_page_negative', 9805, '/trips?page=-1'], ['index_many_page_2abc', 9805, '/trips?page=2abc'],
      ['index_many_page_out', 9805, '/trips?page=4'], ['index_many_extra_param', 9805, '/trips?page=2&view=cards'],
      ['show_leipzig', 9801, '/trips/980101'], ['show_grenzgang', 9801, '/trips/980102'],
      ['show_short_hop', 9801, '/trips/980106'], ['show_ny', 9802, '/trips/980201'],
      ['show_utc', 9803, '/trips/980301'], ['show_described', 9803, '/trips/980302']
    ]
  end

  def capture(name, user_id, path)
    Rails.cache.clear
    sign_in User.find(user_id)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    html = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join("pages/#{name}.html"), html)
    else
      expect(dir.join("pages/#{name}.html").read).to eq(html)
    end
    sign_out :user
    { name:, user_id:, path:, title: doc.at_css('title').text }
  end

  it 'writes the trips pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    expect(ENV.values_at('TIME_ZONE', 'PRINT_ORDER_URL')).to eq([nil, nil])

    travel_to now do
      users = create_users!
      insert!
      write_json('pages.json', { pages: pages.map { |name, user_id, path| capture(name, user_id, path) } })
      write_json('seed.json', { users:, countries:, sources:, trips:, points:, notes:, rich_texts:, shared_links:,
                                posters:, route_videos: })
    end
  end

  it 'writes the day-data corpus' do
    travel_to now do
      create_users!
      insert!
      cases = [980_101, 980_102, 980_106, 980_201, 980_301].map do |id|
        trip = Trip.find(id)
        zone = trip.user.timezone_iana
        { trip_id: id, user_id: trip.user_id, from: trip.started_at.to_i, to: trip.ended_at.to_i,
          gap: trip.user.safe_settings.minutes_between_routes * 60, iana: zone,
          windows_json: trip.primary_device_windows.to_json,
          stats: trip.day_stats(zone).sort.map do |day, stat|
            { day: day.iso8601, first: stat[:first_time].strftime('%Y-%m-%dT%H:%M:%S'),
              last: stat[:last_time].strftime('%Y-%m-%dT%H:%M:%S'), distance_m: stat[:distance_m].round(6) }
          end }
      end
      write_json('windows.json', { trips: cases })
    end
  end

  it 'writes the duration and precision corpus' do
    zones = %w[Europe/Berlin America/New_York UTC Asia/Kathmandu]
    spans = [%w[2026-05-09T06:00:00Z 2026-05-12T20:00:00Z], %w[2026-01-31T09:00:00Z 2026-03-02T07:00:00Z],
             %w[2026-01-31T09:00:00Z 2026-02-02T07:00:00Z], %w[2026-04-30T10:00:00Z 2026-05-01T09:00:00Z],
             %w[2025-12-31T23:30:00Z 2026-01-01T00:15:00Z], %w[2026-02-15T12:00:00Z 2027-04-18T16:00:00Z],
             %w[2026-03-20T09:00:00Z 2026-04-10T07:00:00Z], %w[2026-10-20T12:00:00Z 2026-11-18T08:00:00Z],
             %w[2026-10-28T08:00:00Z 2026-11-25T01:30:00Z],
             %w[2026-06-01T10:00:00Z 2026-06-01T10:59:00Z], %w[2026-06-01T10:00:00Z 2026-06-01T10:00:00Z]]
    durations = zones.product(spans).map do |zone, (from, to)|
      text = Time.use_zone(zone) { helper.trip_duration(Trip.new(started_at: utc(from), ended_at: utc(to))) }
      { zone:, started_at: from, ended_at: to, text: }
    end
    values = [1.0, 1.05, 1.15, 1.25, 1.35, 2.675, 9.95, 12.25, 12.35, 99.95, 100.0, 1234.56, 3.14159,
              10.049999999999999, 10.05, 7.000000000000001, 1.0000000000000002, 1.0e21, 123_456_789.25]
    precision = values.map { |value| { value:, text: helper.number_with_precision(value, precision: 1) } }
    write_json('format.json', { durations:, precision: })
  end

  it 'raises for a previous-month wall time inside a DST gap, which Phoenix hands back' do
    trip = Trip.new(started_at: utc('2026-03-30T08:00:00Z'), ended_at: utc('2026-04-29T00:30:00Z'))
    expect { Time.use_zone('Europe/Berlin') { helper.trip_duration(trip) } }.to raise_error(StandardError)
  end

  it 'writes the trip stream-name corpus' do
    expect(Rails.application.secret_key_base).to eq(secret)
    signed = [980_101, 980_301, 1, 123_456_789].map do |id|
      { trip_id: id, signed: Turbo::StreamsChannel.signed_stream_name(Trip.new(id:)) }
    end
    write_json('streams.json', { secret:, trips: signed })
  end
end
