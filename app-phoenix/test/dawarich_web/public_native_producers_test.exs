defmodule DawarichWeb.PublicNativeProducersTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Test.RailsUser
  @id "ac900000-0000-4000-8000-000000000002"
  setup do
    user =
      RailsUser.insert!(
        %{
          id: 189_002,
          email: "public-producer@example.invalid",
          settings: %{"timezone" => "UTC"}
        },
        ScratchRepo
      )

    ScratchRepo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,name,settings,created_at,updated_at) VALUES($1::text::uuid,$2,3,'Synthetic public','{}',NOW(),NOW())",
      [@id, user.id],
      log: false
    )

    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, repo: ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)
    %{user: user, now: DateTime.utc_now()}
  end

  defp intent do
    rows(
      "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Sharing.EventsWorker' ORDER BY id"
    )
  end

  test "committed point batches invalidate public readers with IDs once without coordinates", c do
    args = %{
      "user_id" => c.user.id,
      "broadcast_id" => Ecto.UUID.generate(),
      "payloads" => [],
      "upserted" => [
        %{
          "id" => 189_002,
          "timestamp" => DateTime.to_unix(c.now),
          "longitude" => 12.5,
          "latitude" => 51.5
        }
      ]
    }

    assert :ok = Dawarich.Points.LiveBroadcastWorker.run(ScratchRepo, args)
    assert [[event]] = intent()
    assert Map.keys(event) |> Enum.sort() == ~w(event_id public_refs user_id)
    reference = Dawarich.Sharing.Events.reference(@id)
    assert event["public_refs"] == [reference]
    assert :ok = Dawarich.Points.LiveBroadcastWorker.run(ScratchRepo, args)
    assert length(intent()) == 1
    Phoenix.PubSub.subscribe(Dawarich.PubSub, Dawarich.Sharing.Events.topic(@id))
    assert :ok = Dawarich.Sharing.EventsWorker.run(ScratchRepo, event)
    assert_receive {:share_invalidated, ^reference}
    assert :ok = Dawarich.Sharing.EventsWorker.run(ScratchRepo, event)
    refute_receive {:share_invalidated, ^reference}
  end

  test "privacy radius and place tag producers enqueue committed invalidation and roll back with writes",
       c do
    ScratchRepo.query!(
      "INSERT INTO tags(id,user_id,name,created_at,updated_at) VALUES(189002,$1,'Synthetic privacy',NOW(),NOW())",
      [c.user.id],
      log: false
    )

    ctx = %{locale: "en", now: c.now}

    assert {:error, :probe} =
             ScratchRepo.transaction(fn ->
               assert {:ok, _} =
                        Dawarich.Tags.Writes.update(
                          ScratchRepo,
                          c.user,
                          189_002,
                          %{"privacy_radius_meters" => "500"},
                          ctx
                        )

               assert length(intent()) == 1
               ScratchRepo.rollback(:probe)
             end)

    assert intent() == []

    assert {:ok, _} =
             Dawarich.Tags.Writes.update(
               ScratchRepo,
               c.user,
               189_002,
               %{"privacy_radius_meters" => "500"},
               ctx
             )

    assert length(intent()) == 1

    assert {:ok, %{id: place}} =
             Dawarich.Places.WebWrite.run(
               ScratchRepo,
               :create,
               c.user,
               nil,
               %{
                 "name" => "Synthetic private",
                 "latitude" => "51.5",
                 "longitude" => "12.5",
                 "tag_ids" => ["189002"]
               },
               ctx
             )

    assert is_integer(place)
    assert length(intent()) == 3
  end
end
