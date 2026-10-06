defmodule DawarichWeb.A12f3aQClosureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-09-26 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    saved = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    env = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, saved)
      if env, do: System.put_env("SELF_HOSTED", env), else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 5290,
        email: "q-closure@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: Accounts.get(user.id), context: %{now: @now, locale: "en", self_hosted: true}}
  end

  @tag a12f3a_q06: true
  test "Q06: single-month and all-month stats update matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    Ownership.put!(Repo, "command:stats.calculate_month", :oban)

    for row <- fixture("06") do
      Repo.query!("DELETE FROM job_outbox", [])

      assert {:ok, result} =
               Dawarich.Stats.WebCommands.update(Repo, user, "2024", row["input"], ctx)

      assert result.status == row["status"]
      assert result.path == row["location"]
      assert %{Atom.to_string(result.flash) => result.message} == row["flash"]

      actual =
        for [args] <-
              Repo.query!(
                "SELECT payload FROM job_outbox ORDER BY created_at, payload->>'month'",
                []
              ).rows,
            do: [args["user_id"], args["year"], args["month"]]

      assert Enum.sort(actual) ==
               Enum.sort(
                 Enum.map(row["jobs"], fn [id, year, month] ->
                   [id, Dawarich.Digests.to_i(year), Dawarich.Digests.to_i(month)]
                 end)
               )

      assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
    end

    for mode <- ["true", "false", nil] do
      set_mode(mode)
      Repo.query!("DELETE FROM job_outbox", [])
      conn = write(user, :post, "/stats/2024/all/update", %{"_method" => "put"})
      assert conn.status == 303
      assert get_resp_header(conn, "location") == ["http://www.example.com/stats"]
      assert Repo.query!("SELECT count(*) FROM job_outbox", []).rows == [[12]]
    end
  end

  @tag a12f3a_q02: true
  test "Q02: month comparisons and empty months matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    stat!(user.id, %{year: 2024, month: 3, distance: 1000})
    page_ctx = Map.put(ctx, :base_url, "http://www.example.com")

    for row <- fixture("02") do
      Repo.query!("UPDATE stats SET daily_distance=$1 WHERE user_id=$2", [row["input"], user.id])

      if row["status"] == 500 do
        assert_raise ArgumentError, fn ->
          DawarichWeb.StatsLive.Month.page(user, %{"year" => "2024", "month" => "3"}, page_ctx)
        end
      else
        page =
          DawarichWeb.StatsLive.Month.page(user, %{"year" => "2024", "month" => "3"}, page_ctx)

        assert page.data.stat.daily == [[1, 1000]]
        assert page.data.previous == nil
      end
    end

    stat!(user.id, %{year: 2024, month: 1, distance: 9000, daily_distance: [[1, 9000]]})

    january =
      DawarichWeb.StatsLive.Month.page(user, %{"year" => "2024", "month" => "1"}, page_ctx)

    assert january.data.previous == nil
    assert january.data.average_km == 5

    assert DawarichWeb.StatsLive.Month.page(user, %{"year" => "2024", "month" => "2"}, page_ctx).data.stat ==
             nil
  end

  @tag a12f3a_q03: true
  test "Q03: insights index and year/month selection matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    stat!(user.id, %{year: 2024, month: 3, distance: 1000, daily_distance: nil})
    context = Dawarich.Stats.context(user, @now, true)

    for row <- fixture("03") do
      if row["status"] == 500 do
        assert_raise ArgumentError, fn -> Dawarich.Insights.page(user, row["input"], context) end
      else
        Repo.query!("UPDATE stats SET daily_distance='[[1, 1000]]'::jsonb WHERE user_id=$1", [
          user.id
        ])

        stat!(user.id, %{year: 2024, month: 4, distance: 1000, daily_distance: [[1, 1000]]})

        assert Dawarich.Insights.page(user, row["input"], context).selected_month ==
                 row["selected_month"]
      end
    end

    Repo.query!("UPDATE stats SET daily_distance='[[1, 1000]]'::jsonb WHERE user_id=$1", [user.id])

    assert Dawarich.Insights.page(user, %{}, context).year == 2024
  end

  @tag a12f3a_q04: true
  test "Q04: insights details data and synchronous digest fill matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    stat!(user.id, %{
      year: 2024,
      month: 3,
      distance: 1000,
      daily_distance: [[1, 1000]],
      updated_at: ~N[2026-09-24 12:00:00]
    })

    for row <- fixture("04") do
      if row["state"] == "cold",
        do: Repo.query!("DELETE FROM digests WHERE user_id=$1", [user.id]),
        else:
          Repo.query!(
            "UPDATE digests SET distance=9, travel_patterns='{}', updated_at='2026-09-23 12:00:00' WHERE user_id=$1",
            [user.id]
          )

      page =
        Dawarich.Insights.Details.load(user, %{"year" => "2024", "month" => "3"},
          fill: true,
          now: @now,
          self_hosted: true
        )

      refute page.rails
      assert page.yearly["distance"] == 1000
      assert page.monthly["distance"] == 1000

      actual =
        Repo.query!(
          "SELECT year, month, period_type, distance, travel_patterns, monthly_distances FROM digests WHERE user_id=$1 ORDER BY period_type",
          [user.id]
        ).rows

      expected =
        Enum.map(row["digests"], fn d ->
          [
            d["year"],
            d["month"],
            if(d["period_type"] == "monthly", do: 0, else: 1),
            d["distance"],
            d["travel_patterns"],
            d["monthly_distances"]
          ]
        end)

      assert actual == expected
    end

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
  end

  @tag a12f3a_q05: true
  test "Q05: insights details frame and transport tails matches current Rails contract without a native-owner Rails effect",
       %{user: user} do
    for row <- fixture("05") do
      set_mode(to_string(row["self_hosted"]))

      conn =
        RailsUser.signed_in(user.id)
        |> put_req_header("turbo-frame", "insights_details")
        |> get("/insights/details?year=all")

      assert conn.status == row["status"]
      assert conn.resp_body =~ ~s(<turbo-frame id="insights_details">)
      refute conn.resp_body =~ "<!DOCTYPE"
      assert get_resp_header(conn, "cache-control") == [row["cache_control"]]
    end

    conn = get(build_conn(), "/insights/details?year=all")
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
  end

  @tag a12f3a_q09: true
  test "Q09: digest generation http producer matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    stat!(user.id, %{year: 2024, month: 3, distance: 1000})
    stat!(user.id, %{year: 2026, month: 3, distance: 1000})
    Ownership.put!(Repo, "command:digests.calculate_year", :oban)

    for row <- fixture("09") do
      Repo.query!("DELETE FROM job_outbox", [])
      assert {:ok, result} = Dawarich.Digests.WebCommands.create(Repo, user, row["input"], ctx)
      assert result.status == row["status"]
      assert result.path == row["location"]
      assert %{Atom.to_string(result.flash) => result.message} == row["flash"]

      actual =
        for [args] <- Repo.query!("SELECT payload FROM job_outbox", []).rows,
            do: [args["user_id"], args["year"]]

      assert actual == row["jobs"]
    end

    for mode <- ["true", "false", nil] do
      set_mode(mode)
      Repo.query!("DELETE FROM job_outbox", [])
      conn = write(user, :post, "/digests", %{"year" => "2024"})
      assert conn.status == 303
      assert get_resp_header(conn, "location") == ["http://www.example.com/digests"]

      assert Repo.query!("SELECT command_type FROM job_outbox", []).rows == [
               ["digests.calculate_year"]
             ]
    end

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
  end

  @tag a12f3a_q07: true
  test "Q07: full stats recalculation producer matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    Ownership.put!(Repo, "command:stats.full_recalculation", :oban)

    for stamp <- [~U[2024-03-05 00:00:00Z], ~U[2024-04-05 00:00:00Z]],
        do: point!(user.id, %{timestamp: DateTime.to_unix(stamp)})

    source = fixture("07")

    for _ <- 1..2 do
      assert {:ok, result} = Dawarich.Stats.WebCommands.update_all(Repo, user, ctx)
      assert result.status == source["status"]
      assert %{Atom.to_string(result.flash) => result.message} == source["flash"]
      assert Repo.query!("SELECT count(*) FROM job_outbox", []).rows == [[1]]
    end

    assert Repo.query!("SELECT command_type FROM job_outbox", []).rows == [
             ["stats.full_recalculation"]
           ]

    [args] = Repo.query!("SELECT payload FROM job_outbox", []).rows |> hd()
    assert {:ok, ^args} = Dawarich.Stats.FullRecalculationWorker.args_from_command(1, args)
    years = Dawarich.Stats.TrackedMonths.call(Repo, user.id)

    actual =
      for %{year: year, months: months} <- years,
          month <- months,
          do: [
            user.id,
            year,
            Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month)) +
              1
          ]

    assert actual == source["jobs"]
    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
  end

  @tag a12f3a_q08: true
  test "Q08: private digest index and show residuals matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    digest!(user.id, %{year: 2024})
    digest!(user.id, %{year: 2026})
    page_ctx = Map.put(ctx, :base_url, "http://www.example.com")

    for row <- fixture("08") do
      if row["attributes"] do
        attrs = row["input"]

        Repo.query!(
          "UPDATE digests SET toponyms=$1, first_time_visits=$2, time_spent_by_location=$3 WHERE user_id=$4 AND year=2024",
          [
            attrs["toponyms"],
            attrs["first_time_visits"] || %{},
            attrs["time_spent_by_location"] || %{},
            user.id
          ]
        )
      else
        Repo.query!("UPDATE digests SET toponyms=$1 WHERE user_id=$2 AND year=2024", [
          row["input"],
          user.id
        ])
      end

      if row["status"] == 500 do
        assert_raise ArgumentError, fn ->
          DawarichWeb.DigestsLive.Show.page(user, %{"year" => "2024"}, page_ctx)
        end
      else
        assert DawarichWeb.DigestsLive.Show.page(user, %{"year" => "2024"}, page_ctx).digest.year ==
                 2024
      end
    end

    context = Dawarich.Stats.context(user, @now, true)
    assert Enum.map(Dawarich.Digests.index(user.id, context).digests, & &1.year) == [2024]
    assert DawarichWeb.DigestsLive.Show.page(user, %{"year" => "2023"}, page_ctx) == :not_found
  end

  @tag a12f3a_q11: true
  test "Q11: digest sharing mutation matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    rows = fixture("11")
    digest!(user.id, %{year: 2024, sharing_uuid: Ecto.UUID.dump!(hd(rows)["uuid"])})
    ctx = Map.put(ctx, :base_url, "http://www.example.com")

    for row <- rows do
      assert {:ok, result} =
               Dawarich.Digests.Sharing.update(Repo, user, "2024", row["params"], ctx)

      assert result.settings == row["settings"]
      assert result.body == row["body"]
      assert result.uuid == row["uuid"]
    end

    conn =
      write(user, :patch, "/digests/2024/sharing", %{
        "enabled" => "1",
        "expiration" => "1h",
        "format" => "json"
      })

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["success"]

    assert {:ok, shifted} =
             Dawarich.Digests.Sharing.update(
               Repo,
               user,
               "2024",
               %{"enabled" => "1", "expiration" => "1h"},
               %{ctx | now: ~U[2026-10-25 00:30:00Z]}
             )

    assert shifted.settings["expires_at"] == "2026-10-25T02:30:00+01:00"
  end

  @tag a12f3a_q10: true
  test "Q10: digest deletion and failure boundary matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    digest!(user.id, %{year: 2024})
    digest!(user.id, %{year: 2024, month: 3, period_type: 0})
    other = RailsUser.insert!(%{id: 5291, email: "q-other@dawarich.test"})
    digest!(other.id, %{year: 2024})

    for row <- fixture("10") do
      assert {:ok, result} = Dawarich.Digests.WebCommands.destroy(Repo, user, "2024", ctx)
      assert result.status == row["status"]
      assert result.path == row["location"]
      assert %{Atom.to_string(result.flash) => result.message} == row["flash"]

      assert Repo.query!(
               "SELECT count(*) FROM digests WHERE user_id=$1 AND year=2024 AND period_type=1",
               [user.id]
             ).rows == [[row["remaining"]]]
    end

    assert Repo.query!("SELECT count(*) FROM digests", []).rows == [[2]]
    digest!(user.id, %{year: 2024})
    conn = write(user, :post, "/digests/2024", %{"_method" => "delete"})
    assert conn.status == 303
    assert Repo.query!("SELECT count(*) FROM digests", []).rows == [[2]]
    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
  end

  @tag a12f3a_q12: true
  test "Q12: public yearly digest and expiration matches current Rails contract without a native-owner Rails effect",
       %{user: user, context: ctx} do
    stamp = NaiveDateTime.utc_now(:second)

    Dawarich.Test.SeedIds.insert_all!(Repo, "countries", [
      %{name: "Germany", iso_a2: "DE", iso_a3: "DEU", created_at: stamp, updated_at: stamp}
    ])

    uuid = hd(fixture("12"))["uuid"]

    digest!(user.id, %{
      year: 2024,
      distance: 50_000,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      toponyms: [toponym("Germany", ["Berlin"])],
      first_time_visits: %{"countries" => ["Germany"], "cities" => ["Berlin"]},
      monthly_distances: %{"3" => 1000},
      time_spent_by_location: %{"countries" => [%{"name" => "Germany", "minutes" => 1000}]}
    })

    assert_public_cases(
      user,
      ctx,
      "12",
      "digest",
      "digests",
      uuid,
      "div.max-w-xl.mx-auto.px-4.py-8"
    )
  end

  defp assert_public_cases(user, ctx, task, kind, table, uuid, selector) do
    for row <- fixture(task) do
      settings = %{
        "enabled" => row["state"] != "disabled",
        "expiration" => "1h",
        "expires_at" =>
          DateTime.to_iso8601(
            DateTime.add(@now, if(row["state"] == "expired", do: -1, else: 3600))
          )
      }

      Repo.query!("UPDATE #{table} SET sharing_settings=$1 WHERE user_id=$2", [settings, user.id])

      Repo.query!("UPDATE users SET plan=$1 WHERE id=$2", [
        if(row["state"] == "partial", do: 0, else: 1),
        user.id
      ])

      set_mode(if(row["state"] == "partial", do: "false", else: "true"))
      conn = build_conn() |> assign(:now, ctx.now) |> get("/shared/#{kind}/#{uuid}")
      assert conn.status == row["status"]
      head = build_conn() |> assign(:now, ctx.now) |> head("/shared/#{kind}/#{uuid}")
      assert head.status == conn.status
      assert head.resp_body == ""
      assert get_resp_header(conn, "cache-control") == [row["cache_control"]]

      if row["html"] do
        html =
          conn.resp_body
          |> LazyHTML.from_document()
          |> LazyHTML.query(selector)
          |> LazyHTML.to_html()

        assert Dawarich.Test.ChartkickHTML.charts(html) ==
                 Dawarich.Test.ChartkickHTML.charts(row["html"])

        assert normalize_public(html) == normalize_public(row["html"]),
               inspect(first_difference(normalize_public(html), normalize_public(row["html"])),
                 limit: :infinity
               )

        refute html =~ "data-api-key"
      else
        assert get_resp_header(conn, "location") == ["http://www.example.com/"]
      end

      assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
    end

    assert (build_conn() |> get("/shared/#{kind}/unknown")).status == 302
  end

  defp first_difference(a, a), do: nil

  defp first_difference(a, b) when is_list(a) and is_list(b) and length(a) == length(b),
    do: Enum.find_value(Enum.zip(a, b), fn {x, y} -> first_difference(x, y) end)

  defp first_difference(a, b) when is_tuple(a) and is_tuple(b),
    do: first_difference(Tuple.to_list(a), Tuple.to_list(b))

  defp first_difference(a, b), do: {a, b}

  defp normalize_public(html),
    do:
      html |> Dawarich.Test.ChartkickHTML.without_charts() |> Dawarich.Test.ParityHTML.normalize()

  defp fixture(task),
    do: File.read!("test/fixtures/stats/a12f3a-q#{task}.json") |> Jason.decode!()

  defp set_mode(nil), do: System.delete_env("SELF_HOSTED")
  defp set_mode(value), do: System.put_env("SELF_HOSTED", value)

  defp write(user, method, path, attrs) do
    session = RailsUser.session(user.id)
    raw = Plug.Conn.Query.encode(attrs)

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(raw)))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
    |> dispatch(@endpoint, method, path, raw)
  end
end
