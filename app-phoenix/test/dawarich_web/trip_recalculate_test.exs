defmodule DawarichWeb.TripRecalculateTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  import Plug.Conn
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{RailsUser, ParityHTML}
  alias Dawarich.Trips.WebRecalculate
  alias DawarichWeb.{TripActions, RailsCsrf}
  @now ~U[2026-10-03 11:00:00.000000Z]

  defmodule FailedAfterOutbox do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      result = Dawarich.ScratchRepo.query!(sql, params, opts)

      if String.contains?(sql, "INSERT INTO public.job_outbox"),
        do:
          Dawarich.ScratchRepo.query!("UPDATE trips SET user_id = NULL WHERE id = $1", [
            Enum.at(params, 2)
          ])

      result
    end
  end

  defp trip(id, user, offset, demo \\ false) do
    stamp = DateTime.to_naive(@now)

    ScratchRepo.insert_all("trips", [
      %{
        id: id,
        user_id: user.id,
        name: "Auwald",
        demo: demo,
        started_at: stamp,
        ended_at: NaiveDateTime.add(stamp, 3600),
        last_recalculated_at: if(offset, do: NaiveDateTime.add(stamp, -offset)),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    id
  end

  defp counts,
    do:
      rows(
        "SELECT (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM phoenix.rails_commands)"
      )

  defp stamp(id),
    do: rows("SELECT last_recalculated_at, updated_at FROM trips WHERE id = $1", [id])

  @tag a12f3a_t07: true
  test "recalculation is strict at sixty seconds and preserves owner phases" do
    user =
      RailsUser.insert!(
        %{id: 898_801, email: "a8-recalc@example.invalid", settings: %{}},
        ScratchRepo
      )
      |> Map.put(:active_until, ~U[3026-01-01 00:00:00Z])

    foreign = %{user | id: 898_802}
    ctx = %{now: @now, locale: "en"}
    Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)

    for {offset, result, id} <- [
          {nil, :queued, 898_810},
          {59, :cooldown, 898_811},
          {60, :cooldown, 898_812},
          {61, :queued, 898_813}
        ] do
      trip(id, user, offset)
      before = counts()
      assert {:ok, ^result} = WebRecalculate.run(ScratchRepo, user, id, ctx)
      [[at, updated]] = stamp(id)
      assert updated == DateTime.to_naive(@now)

      if result == :cooldown do
        assert counts() == before
        assert at == @now |> DateTime.add(-offset) |> DateTime.to_naive()
      else
        assert at == DateTime.to_naive(@now)

        assert rows("SELECT payload FROM job_outbox WHERE aggregate_id = $1", [id]) == [
                 [%{"trip_id" => id, "distance_unit" => "km"}]
               ]
      end
    end

    assert {:error, :not_found} = WebRecalculate.run(ScratchRepo, foreign, 898_810, ctx)

    assert {:replay, _} =
             WebRecalculate.run(ScratchRepo, %{user | active_until: nil}, 898_810, ctx)

    trip(898_814, user, nil)
    Ownership.put!(ScratchRepo, "command:trips.calculate", :sidekiq)
    before = counts()
    old = stamp(898_814)
    assert {:replay, _} = WebRecalculate.run(ScratchRepo, user, 898_814, ctx)
    assert stamp(898_814) == old
    assert counts() == before
    trip(898_815, user, nil, true)
    assert {:replay, _} = WebRecalculate.run(ScratchRepo, user, 898_815, ctx)
    assert counts() == before
    Ownership.put!(ScratchRepo, "command:trips.calculate", :oban)
    assert {:ok, :queued} = WebRecalculate.run(ScratchRepo, user, 898_815, ctx)
    before = counts()

    assert_raise Postgrex.Error, fn ->
      WebRecalculate.run(FailedAfterOutbox, user, 898_814, ctx)
    end

    assert stamp(898_814) == old
    assert counts() == before

    tasks =
      for _ <- 1..2, do: Task.async(fn -> WebRecalculate.run(ScratchRepo, user, 898_814, ctx) end)

    assert Enum.sort(Enum.map(tasks, &Task.await/1)) == [{:ok, :cooldown}, {:ok, :queued}]
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id = 898814") == [[1]]

    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)

    responses =
      File.read!("test/fixtures/trips/remaining/responses.json")
      |> Jason.decode!()
      |> Map.fetch!("responses")

    for {offset, label, id} <- [
          {nil, "nil", 898_820},
          {59, "59", 898_822},
          {60, "60", 898_824},
          {61, "61", 898_826}
        ],
        format <- [:html, :turbo_stream] do
      id = id + if(format == :html, do: 0, else: 1)
      trip(id, user, offset)
      name = "recalculate_#{label}_#{if format == :html, do: "html", else: "stream"}_oban"
      expected = Enum.find(responses, &(&1["name"] == name))
      session = RailsUser.session(user.id)

      conn =
        Plug.Test.conn(:post, "/trips/#{id}/recalculate", "")
        |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
        |> assign(:current_user, user)
        |> assign(:rails_session, session)
        |> assign(:now, @now)
        |> assign(:a8_format, format)
        |> Map.put(:path_params, %{"id" => Integer.to_string(id)})
        |> TripActions.call(:recalculate)

      assert conn.status == expected["status"], name

      if format == :html do
        assert get_resp_header(conn, "location") == ["http://www.example.com/trips/#{id}"]

        assert Dawarich.Test.RailsFormRequests.rails_session(conn)["flash"]["flashes"] ==
                 expected["flash"]
      else
        golden = File.read!("test/fixtures/trips/remaining/pages/#{name}.html")
        assert ParityHTML.normalize(conn.resp_body) == ParityHTML.normalize(golden), name
        assert ParityHTML.stimulus(conn.resp_body) == ParityHTML.stimulus(golden)
      end
    end

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert RailsCsrf.masked_token(RailsUser.session(user.id)) != nil
  end
end
