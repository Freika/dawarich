defmodule DawarichWeb.TripMissingDataTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Dawarich.Test.RailsFormRequests
  require Phoenix.LiveViewTest
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML, MapStimulus}
  alias Dawarich.{TripPage, Trips.ShowCalculation}
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-03 10:00:00.000000Z]
  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")

  defmodule SpyRepo do
    defdelegate transaction(fun), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      if String.contains?(sql, "INSERT INTO public.job_outbox") do
        Process.put(:show_productions, Process.get(:show_productions, 0) + 1)
        if Process.delete(:show_failure), do: raise("show producer-start failure")
      end

      Dawarich.Repo.query!(sql, params, opts)
    end
  end

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp seed(entry) do
    actor = entry["before"]["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-showmissing-#{actor["id"]}@example.invalid",
      api_key: "a8r-k-#{actor["id"]}",
      settings: actor["settings"]
    })

    [trip] = entry["before"]["trips"]

    TripsSeeds.trip!(%{
      id: trip["id"],
      user_id: trip["user_id"],
      name: trip["name"],
      demo: trip["demo"],
      distance: trip["distance"],
      visited_countries: trip["visited_countries"],
      source_identifier: trip["source_identifier"],
      started_at: naive(trip["started_at"]),
      ended_at: naive(trip["ended_at"]),
      path: if(trip["path"] == [], do: nil, else: trip["path"])
    })

    if trip["path"] == [], do: TripsSeeds.empty_path!(trip["id"])

    for point <- entry["before"]["points"],
        do:
          TripsSeeds.point!(%{
            id: point["id"],
            user_id: point["user_id"],
            timestamp: point["timestamp"],
            at: point["lonlat"]
          })

    Ownership.put!(
      Repo,
      "command:trips.calculate",
      String.to_existing_atom(entry["request"]["owner"])
    )

    {Dawarich.Accounts.get(actor["id"]), trip["id"]}
  end

  defp shell(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query("#trip-shell") |> LazyHTML.to_html()

  test "Cloud calculation documents produce native work without Rails effects" do
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    entry = Enum.find(@effects, &(&1["name"] == "show_nil_path_oban"))
    {user, id} = seed(entry)
    System.put_env("SELF_HOSTED", "false")
    assert ShowCalculation.admitted?(Repo, user, id, @now)
    assert {:ok, :queued} = ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
    assert commands() == []
    TripsSeeds.path!(id, [[12.3712, 51.3391], [12.3801, 51.3422]])
    assert ShowCalculation.admitted?(Repo, user, id, @now)
    assert {:ok, :ready} = ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[1]]
  end

  test "an owner flip before document production replays the Rails GET and response" do
    entry = Enum.find(@effects, &(&1["name"] == "show_nil_path_sidekiq"))
    {user, id} = seed(entry)
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    golden = File.read!("test/fixtures/trips/remaining/pages/show_nil_path_sidekiq.html")
    upstream = upstream!()
    handler = {__MODULE__, :owner_flip}

    :ok =
      :telemetry.attach(
        handler,
        [:dawarich, :repo, :query],
        fn _, _, meta, _ ->
          if meta.query ==
               "SELECT owner FROM phoenix.job_owners WHERE key = 'command:trips.calculate'" and
               Process.delete(:flip_show_owner) do
            Ownership.put!(Repo, "command:trips.calculate", :sidekiq)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    puma =
      Task.async(fn ->
        socket = Dawarich.Test.RawHTTP.accept(upstream)
        {head, rest} = Dawarich.Test.RawHTTP.read_head(socket)

        Dawarich.Test.RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-type: text/html; charset=utf-8\r\ncontent-length: #{byte_size(golden)}\r\n\r\n" <>
            golden
        )

        :gen_tcp.close(socket)
        {Dawarich.Test.RawHTTP.request_line(head), rest}
      end)

    before = Repo.query!("SELECT to_jsonb(t) FROM trips t WHERE id=$1", [id]).rows
    Process.put(:flip_show_owner, true)
    before_user = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [user.id]).rows
    path = entry["request"]["path"]
    conn = RailsUser.signed_in(user.id) |> get(path)
    assert conn.status == 200
    assert conn.resp_body == golden
    assert Task.await(puma) == {"GET #{path} HTTP/1.1", ""}
    assert Process.get(:flip_show_owner) == nil
    assert Repo.query!("SELECT to_jsonb(t) FROM trips t WHERE id=$1", [id]).rows == before

    assert Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [user.id]).rows ==
             before_user

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
    assert commands() == []
  end

  test "missing show renders Rails states and queues only on document mount" do
    Repo.query!("DELETE FROM countries")

    for entry <- Enum.sort_by(@effects, &(&1["request"]["owner"] != "oban")),
        String.starts_with?(entry["name"], "show_") or
          String.starts_with?(entry["name"], "demo_show_"),
        entry["request"]["fault"] == nil,
        entry["name"] not in ~w(show_repeat_sidekiq show_repeat_oban) do
      {user, id} = seed(entry)
      assert {:ok, page} = TripPage.load(user, id, @now)
      before = Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows
      eligible = entry["queue"]["commands"] != []

      if eligible and entry["request"]["owner"] == "sidekiq" do
        refute ShowCalculation.admitted?(Repo, user, id, @now)

        assert {:replay, _} =
                 ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})

        assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
                 before
      else
        assert ShowCalculation.admitted?(Repo, user, id, @now)
        assert {:ok, _} = ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})

        assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
                 [[length(entry["queue"]["outbox"])]]
      end

      Process.put(:show_productions, 0)
      before = Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows
      assert {:ok, _} = ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: true})
      assert Process.get(:show_productions) == 0

      assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
               before

      for connected <- [false, true] do
        socket = %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, current_user: user, now: @now, locale: "en"},
          transport_pid: if(connected, do: self())
        }

        result =
          case DawarichWeb.TripsLive.Show.mount(%{"id" => to_string(id)}, %{}, socket) do
            {:ok, socket} -> {:ok, socket, []}
            result -> result
          end

        assert {:ok, mounted, options} = result

        assert mounted.assigns.page.map_state == page.map_state
        assert options[:temporary_assigns] == [page: nil]
        assert mounted.redirected == nil

        assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
                 before
      end

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.TripsLive.Show.render/1, %{
          page: page,
          locale: "en",
          rails_csrf_token: "CSRF",
          base_url: "http://www.example.com"
        })

      golden = File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")
      actual = ParityHTML.normalize(shell(html))
      expected = ParityHTML.normalize(shell(golden))

      assert actual == expected,
             entry["name"] <> ": " <> ParityHTML.first_difference(actual, expected)

      attributes = html |> MapStimulus.prepare() |> MapStimulus.attributes(["#trip-shell"])

      expected_attributes =
        golden |> MapStimulus.prepare() |> MapStimulus.attributes(["#trip-shell"])

      assert attributes == expected_attributes,
             inspect(
               Enum.zip(attributes, expected_attributes) |> Enum.find(fn {a, b} -> a != b end),
               limit: :infinity
             )

      if entry["request"]["owner"] == "oban" and eligible do
        Process.put(:show_failure, true)

        assert_raise RuntimeError, "show producer-start failure", fn ->
          ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})
        end

        assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
                 before

        Ownership.put!(Repo, "command:trips.calculate", :sidekiq)

        assert {:replay, _} =
                 ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})

        assert Repo.query!("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]).rows ==
                 before
      end

      Repo.query!("UPDATE trips SET visited_countries = '[1]'::jsonb WHERE id=$1", [id])
      assert TripPage.gate(user, id) == :rails

      assert {:replay, _} =
               ShowCalculation.run(SpyRepo, user, id, %{now: @now, connected: false})
    end

    assert commands() == []
  end
end
