defmodule DawarichWeb.StatsParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Repo
  alias Dawarich.Test.{ChartkickHTML, ParityHTML, RailsUser}

  @dir "test/fixtures/stats"
  @env ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY STORE_GEODATA TIME_ZONE MANAGER_URL)
  @sampled ~r/(underline hover:no-underline) text-(?:info|success|warning|error|accent|secondary|primary)"/

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for key <- @env, do: System.delete_env(key)
    System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
    on_exit(fn -> System.delete_env("JWT_SECRET_KEY") end)
  end

  for html <- Path.wildcard("test/fixtures/stats/*.html"),
      file = Path.rootname(html) <> ".json" do
    @name Path.basename(file, ".json")
    @title_ed @name in ~w(year_ca digests_ca digest_full_fr)
    @test_name if(@title_ed,
                 do: "#{@name} matches Rails except title double-escaping (ED-551)",
                 else:
                   "#{@name} preserves Rails data charts and titles with native sharing entries"
               )

    @test_name if(String.starts_with?(@name, "digest"),
                 do:
                   "#{@name} native persisted values access and localized charts match the source",
                 else: @test_name
               )

    if @name in ~w(index_en index_nongeo_en index_lite_en year_lite_en),
      do: @tag(a12f3a_q01: true)

    test @test_name do
      state = @dir |> Path.join(@name <> ".json") |> File.read!() |> Jason.decode!()
      {:ok, now, 0} = DateTime.from_iso8601(state["now"])
      user = seed!(state, now)
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      context = %{
        locale: locale,
        now: now,
        self_hosted: state["self_hosted"],
        base_url: "http://www.example.com",
        rails_csrf_token: "CSRF",
        current_user: user
      }

      {kind, params} = route(state["path"])
      rails = File.read!(Path.join(@dir, @name <> ".html"))
      assigns = source(user, params, context, kind)

      case kind do
        :digest ->
          native_digest(user, params, context, assigns, rails)

        :stats ->
          native_stats(user, params, context, assigns, rails)

        :month ->
          phoenix =
            render_component(&DawarichWeb.StatsLive.Month.render/1, Map.merge(context, assigns))

          if rails =~ ~s(id="sharing_modal") do
            path = URI.parse(state["path"]).path <> "/sharing"

            entries =
              phoenix
              |> LazyHTML.from_fragment()
              |> LazyHTML.query("a[href='#{path}']")
              |> LazyHTML.attribute("href")

            assert entries == [path, path]
            refute phoenix =~ ~s(id="sharing_modal")

            assert_share_values(
              user,
              params,
              DawarichWeb.StatsLive.Month,
              now,
              state["self_hosted"],
              locale
            )
          end

          if rails =~ "/assets/backgrounds/months/",
            do: assert(phoenix =~ "/native/backgrounds/months/")

          assert normalized(phoenix) == normalized(rails)

          assert ParityHTML.stimulus(Dawarich.Test.NativeM4Corpus.reports(phoenix)) ==
                   ParityHTML.stimulus(Dawarich.Test.NativeM4Corpus.reports(rails))

          assert charts(phoenix) == charts(rails)
      end

      title =
        render_component(
          &DawarichWeb.Layouts.root/1,
          Map.merge(context, %{inner_content: "", page_title: assigns.page_title})
        )
        |> LazyHTML.from_document()
        |> LazyHTML.query("title")
        |> LazyHTML.text()

      if @title_ed do
        assert state["title"] =~ "&#39;"

        rails_title =
          "<title>#{state["title"]}</title>"
          |> LazyHTML.from_document()
          |> LazyHTML.query("title")
          |> LazyHTML.text()

        assert title == rails_title
      else
        assert title == state["title"]
      end
    end
  end

  defp assert_share_values(user, params, module, now, self_hosted, locale) do
    {resource, table, args, condition} =
      if module == DawarichWeb.StatsLive.Month,
        do:
          {%{
             type: :month,
             owner_id: user.id,
             year: String.to_integer(params["year"]),
             month: String.to_integer(params["month"])
           }, "stats", [String.to_integer(params["year"]), String.to_integer(params["month"])],
           "year=$2 AND month=$3"},
        else:
          {%{type: :digest, owner_id: user.id, year: String.to_integer(params["year"])},
           "digests", [String.to_integer(params["year"])], "year=$2 AND period_type=1"}

    [[uuid, settings]] =
      Repo.query!(
        "SELECT sharing_uuid::text,sharing_settings FROM #{table} WHERE user_id=$1 AND #{condition}",
        [user.id | args],
        log: false
      ).rows

    result =
      Dawarich.Sharing.page(Dawarich.Accounts.Scope.for_user(user, locale), resource, %{},
        now: now,
        self_hosted: self_hosted
      )

    case result do
      {:ok, page} ->
        assert {page.uuid, page.settings} == {uuid, settings}

      {:error, :expired} ->
        assert is_nil(user.active_until) or
                 NaiveDateTime.compare(user.active_until, DateTime.to_naive(now)) != :gt or
                 (resource.type == :month and user.plan == 0 and not self_hosted)
    end

    assert Repo.query!(
             "SELECT sharing_uuid::text,sharing_settings FROM #{table} WHERE user_id=$1 AND #{condition}",
             [user.id | args],
             log: false
           ).rows == [[uuid, settings]]
  end

  defp source(user, params, context, :month),
    do: DawarichWeb.StatsLive.Month.page(user, params, context)

  defp source(user, params, context, :digest) do
    values =
      if params == %{},
        do:
          Dawarich.Digests.index(
            user.id,
            Dawarich.Stats.context(user, context.now, context.self_hosted)
          ),
        else: %{digest: Dawarich.Digests.get(user.id, Dawarich.RubyInteger.to_i(params["year"]))}

    key =
      if params == %{},
        do: "users.digests.index.year_end_digests",
        else: "users.digests.show.year_year_in_review"

    Map.merge(values, %{
      page_title: DawarichWeb.Translate.t(context.locale, key, %{year: params["year"]}),
      table: Dawarich.CountryNames.table()
    })
  end

  defp source(user, params, context, :stats) do
    period = Dawarich.Stats.context(user, context.now, context.self_hosted)

    values =
      if params == %{},
        do:
          Dawarich.Stats.index(
            user,
            period,
            Dawarich.Geocoding.Config.resolve(Dawarich.Repo).store_geodata,
            context.now
          ),
        else: Dawarich.Stats.year(user, Dawarich.RubyInteger.to_i(params["year"]), period)

    key =
      if params == %{}, do: "stats.index.statistics", else: "stats.show.statistics_for_year_year"

    Map.put(
      values,
      :page_title,
      DawarichWeb.Translate.t(context.locale, key, %{year: params["year"]})
    )
  end

  defp native_stats(user, params, context, source, rails) do
    scope = Dawarich.Accounts.Scope.for_user(user, context.locale)
    opts = [now: context.now, self_hosted: context.self_hosted]
    mode = if params == %{}, do: :index, else: :year

    {:ok, data} =
      if mode == :index,
        do: Dawarich.Stats.Pages.index(scope, params, opts),
        else: Dawarich.Stats.Pages.year(scope, params, opts)

    if mode == :index do
      for key <- [:total_distance, :locked_years], do: assert(data[key] == source[key])
      assert data.total_countries == length(source.countries_visited)
      assert data.total_cities == length(source.cities_visited)
      assert data.countries_visited == Enum.sort(source.countries_visited)
      assert data.cities_visited == Enum.sort(source.cities_visited)
      assert Enum.map(data.years, & &1.year) == Enum.map(source.years, & &1.year)
    else
      assert data.distances == source.distances

      assert Enum.map(data.stats, &{&1.month, &1.distance}) ==
               Enum.map(source.stats, &{&1.month, &1.distance})
    end

    html =
      render_component(&DawarichWeb.StatsLive.NativeParts.page/1,
        data: data,
        locale: context.locale,
        mode: mode
      )

    actual =
      LazyHTML.from_document(html)
      |> LazyHTML.query("[data-chart]")
      |> LazyHTML.attribute("data-chart")
      |> Enum.map(&Jason.decode!(&1)["data"])

    expected =
      for chart <- charts(rails),
          not String.starts_with?(chart.id, "chart-year-locked-"),
          do: chart.data

    assert actual ==
             Enum.map(expected, fn points ->
               Enum.map(points, fn [label, value] -> [label, value || 0] end)
             end)

    refute html =~ "data-controller="
    refute html =~ "data-turbo"
  end

  defp native_digest(user, params, context, source, rails) do
    scope = Dawarich.Accounts.Scope.for_user(user, context.locale)
    opts = [now: context.now, self_hosted: context.self_hosted]

    html =
      if params == %{} do
        {:ok, data} = Dawarich.Digests.Pages.index(scope, params, opts)
        assert data.available_years == source.available_years
        assert Enum.map(data.digests, & &1.year) == Enum.map(source.digests, & &1.year)

        for {native, old} <- Enum.zip(data.digests, source.digests),
            key <- [:year, :distance],
            do: assert(native[key] == old[key])

        for {native, old} <- Enum.zip(data.digests, source.digests) do
          assert native.countries_count == Dawarich.Digests.countries_count(old.toponyms)
          assert native.cities_count == Dawarich.Digests.cities_count(old.toponyms)
          assert native.first_time_countries_count == length(old.first_time_countries)
          assert native.first_time_cities_count == length(old.first_time_cities)
          refute Map.has_key?(native, :toponyms)
        end

        render_component(&DawarichWeb.DigestsLive.NativeIndexParts.render/1,
          data: data,
          locale: context.locale
        )
      else
        {:ok, data} = Dawarich.Digests.Pages.get(scope, params, opts)

        for key <- Map.keys(data) -- [:period, :restricted, :unit],
            do: assert(data[key] == source.digest[key])

        summary =
          render_component(&DawarichWeb.DigestsLive.NativeParts.summary/1,
            digest: data,
            locale: context.locale,
            unit: data.unit
          )

        if data.restricted do
          summary
        else
          full =
            render_component(&DawarichWeb.DigestsLive.NativeFullParts.full/1,
              digest: data,
              locale: context.locale,
              unit: data.unit,
              table: source.table
            )

          native_charts =
            LazyHTML.from_document(full)
            |> LazyHTML.query("[data-chart]")
            |> LazyHTML.attribute("data-chart")
            |> Enum.map(&Jason.decode!(&1)["data"])

          assert native_charts == Enum.map(charts(rails), & &1.data)
          summary <> full
        end
      end

    refute html =~ "data-turbo"
    refute html =~ "onclick="
    refute html =~ "Chartkick"
  end

  defp normalized(html),
    do:
      html
      |> Dawarich.Test.NativeM4Corpus.reports()
      |> ChartkickHTML.without_charts()
      |> String.replace("/native/backgrounds/months/", "/assets/backgrounds/months/")
      |> then(&Regex.replace(@sampled, &1, "\\1 text-SAMPLED\""))
      |> ParityHTML.normalize()

  defp charts(html) do
    for chart <- ChartkickHTML.charts(html) do
      if String.starts_with?(chart.id, "chart-year-locked-") do
        assert Enum.all?(chart.data, fn [_label, value] -> value in 5_000..80_000 end)
        %{chart | data: Enum.map(chart.data, fn [label, _] -> [label, :random] end)}
      else
        chart
      end
    end
  end

  defp route("/stats"), do: {:stats, %{}}
  defp route("/digests"), do: {:digest, %{}}

  defp route(path) do
    case String.split(path, "/", trim: true) do
      ["stats", year] -> {:stats, %{"year" => year}}
      ["stats", year, month] -> {:month, %{"year" => year, "month" => month}}
      ["digests", year] -> {:digest, %{"year" => year}}
    end
  end

  defp seed!(state, now) do
    u = state["user"]
    stamp = NaiveDateTime.utc_now(:second)

    RailsUser.insert!(%{
      id: u["id"],
      email: u["email"],
      settings: u["settings"],
      plan: u["plan"],
      status: u["status"],
      active_until: naive(u["active_until"]),
      api_key: u["api_key"],
      points_count: u["points_count"],
      theme: u["theme"]
    })

    Repo.insert_all(
      "countries",
      for(
        [name, a2, a3] <- state["countries"],
        do: %{name: name, iso_a2: a2, iso_a3: a3, created_at: stamp, updated_at: stamp}
      )
    )

    Repo.insert_all(
      "instance_settings",
      for(
        %{"key" => key, "value" => value} <- state["instance_settings"],
        do: %{key: key, value: value, created_at: stamp, updated_at: stamp}
      )
    )

    Repo.insert_all(
      "stats",
      for s <- state["stats"] do
        %{
          id: s["id"],
          user_id: u["id"],
          year: s["year"],
          month: s["month"],
          distance: s["distance"],
          flight_distance: s["flight_distance"],
          daily_distance: s["daily_distance"],
          toponyms: s["toponyms"],
          sharing_settings: s["sharing_settings"],
          sharing_uuid: Ecto.UUID.dump!(s["sharing_uuid"]),
          created_at: naive(s["created_at"]),
          updated_at: naive(s["updated_at"])
        }
      end
    )

    Repo.insert_all(
      "digests",
      for d <- state["digests"] do
        %{
          id: d["id"],
          user_id: u["id"],
          year: d["year"],
          month: d["month"],
          period_type: d["period_type"],
          distance: d["distance"],
          toponyms: d["toponyms"],
          first_time_visits: d["first_time_visits"],
          time_spent_by_location: d["time_spent_by_location"],
          year_over_year: d["year_over_year"],
          all_time_stats: d["all_time_stats"],
          monthly_distances: d["monthly_distances"],
          sharing_settings: d["sharing_settings"],
          sharing_uuid: Ecto.UUID.dump!(d["sharing_uuid"]),
          created_at: naive(d["created_at"]),
          updated_at: naive(d["updated_at"])
        }
      end
    )

    if counts = state["point_counts"],
      do:
        ScratchRepo.query!("INSERT INTO phoenix.stats_point_counts VALUES ($1, $2, $3, $4)", [
          u["id"],
          counts["geocoded"],
          counts["without_data"],
          now
        ])

    Dawarich.Accounts.get(u["id"])
  end

  defp naive(nil), do: nil

  defp naive(iso),
    do: iso |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:microsecond)
end
