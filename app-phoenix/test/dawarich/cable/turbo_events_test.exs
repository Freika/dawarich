defmodule Dawarich.Cable.TurboEventsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Cable.TurboEvents
  alias Dawarich.Test.{A12a, ParityHTML}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    A12a.seed!()
    A12a.start_bus!()
    :ok
  end

  defp heard_all(n), do: for(_ <- 1..n, do: A12a.heard())

  defp same_stream?(rails, phoenix) do
    {r_wrap, r_html} = A12a.split_turbo(rails)
    {p_wrap, p_html} = A12a.split_turbo(phoenix)
    r_wrap == p_wrap and ParityHTML.normalize(r_html) == ParityHTML.normalize(p_html)
  end

  test "a notification event becomes Rails' prepend and badge streams" do
    for name <- ~w(notification_created notification_badge_99_plus notification_badge_99) do
      %{"events" => events, "published" => rails} = A12a.relay!(name)
      A12a.insert_events!(events)
      {:ok, _} = A12a.listen(A12a.relay_broadcasting(name))
      assert TurboEvents.notifications(Dawarich.Jobs.repo(), Dawarich.Repo) == length(events)
      published = heard_all(length(rails))

      assert Enum.zip(rails, published)
             |> Enum.all?(fn {{b, r}, {b2, p}} -> b == b2 and same_stream?(r, p) end),
             name
    end
  end

  test "a soft-deleted user's notification and a deleted notification are skipped" do
    %{"events" => events} = A12a.relay!("notification_soft_deleted_user")
    A12a.insert_events!(events ++ [%{"notification_id" => -1}])
    {:ok, _} = A12a.listen_all()
    assert TurboEvents.notifications(Dawarich.Jobs.repo(), Dawarich.Repo) == 2
    refute_receive {:redix_pubsub, _, _, :pmessage, _}, 300
  end

  test "trip events: path refreshes, finished replaces the frame (with the error line when failed), distance and countries send nothing" do
    for name <- ~w(trip_path trip_finished_ok trip_finished_failed trip_finished_cooling) do
      %{"events" => events, "published" => [{b, rails}]} = A12a.relay!(name)
      A12a.insert_events!(events)
      {:ok, _} = A12a.listen(b)
      assert TurboEvents.trips(Dawarich.Jobs.repo(), Dawarich.Repo, A12a.naive_now()) == 1
      assert {^b, phoenix} = A12a.heard()
      assert same_stream?(rails, phoenix), name
    end

    gone = %{"trip_id" => -1, "kind" => "finished", "distance_unit" => "km", "failed" => false}

    for events <- [
          A12a.relay!("trip_distance")["events"],
          A12a.relay!("trip_countries")["events"],
          [gone]
        ] do
      A12a.insert_events!(events)
      {:ok, _} = A12a.listen_all()
      assert TurboEvents.trips(Dawarich.Jobs.repo(), Dawarich.Repo, A12a.naive_now()) == 1
      refute_receive {:redix_pubsub, _, _, :pmessage, _}, 300
    end

    assert A12a.corpus()["relay"]["trip_show_targets"] ==
             %{"trip_distance" => false, "trip_countries" => false}

    assert A12a.corpus()["relay"]["relay_locale"] == "en"
  end

  test "nothing is claimed while the publisher is down; once it is back each event is published once" do
    A12a.insert_events!(
      A12a.relay!("notification_created")["events"] ++ A12a.relay!("trip_path")["events"]
    )

    A12a.swap_publisher!(A12a.dead_redis_url())
    {:ok, _} = A12a.listen_all()
    assert_raise MatchError, fn -> TurboEvents.drain(Dawarich.Jobs.repo(), Dawarich.Repo) end
    assert A12a.queued() == 2
    refute_receive {:redix_pubsub, _, _, :pmessage, _}, 300

    A12a.swap_publisher!(A12a.test_redis_url())
    assert TurboEvents.drain(Dawarich.Jobs.repo(), Dawarich.Repo) == 2
    assert A12a.heard_count(300) == 3
    assert A12a.queued() == 0
  end
end
