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
                 else: "#{@name} matches the page Rails renders"
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

      {module, params} = route(state["path"])
      assigns = module.page(user, params, context)
      phoenix = render_component(&module.render/1, Map.merge(context, assigns))
      rails = File.read!(Path.join(@dir, @name <> ".html"))

      assert normalized(phoenix) == normalized(rails)
      assert ParityHTML.stimulus(phoenix) == ParityHTML.stimulus(rails)
      assert charts(phoenix) == charts(rails)

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

  defp normalized(html),
    do:
      html
      |> ChartkickHTML.without_charts()
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

  defp route("/stats"), do: {DawarichWeb.StatsLive.Index, %{}}
  defp route("/digests"), do: {DawarichWeb.DigestsLive.Index, %{}}

  defp route(path) do
    case String.split(path, "/", trim: true) do
      ["stats", year] -> {DawarichWeb.StatsLive.Year, %{"year" => year}}
      ["stats", year, month] -> {DawarichWeb.StatsLive.Month, %{"year" => year, "month" => month}}
      ["digests", year] -> {DawarichWeb.DigestsLive.Show, %{"year" => year}}
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
