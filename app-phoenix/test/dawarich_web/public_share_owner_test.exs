defmodule DawarichWeb.PublicShareOwnerTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-07 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    user = RailsUser.insert!(%{id: 64127, email: "public-owner@dawarich.test"})
    uuid = Ecto.UUID.generate()
    settings = %{"enabled" => true, "expiration" => nil}

    stat!(user.id, %{
      year: 2024,
      month: 3,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    digest!(user.id, %{
      year: 2024,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    %{user: user, uuid: uuid}
  end

  @tag public_owner_states: true
  test "public month and digest survive login-locked and NULL-settings owners", %{
    user: user,
    uuid: uuid
  } do
    for {locked_at, settings} <- [
          {DateTime.to_naive(DateTime.utc_now()), %{}},
          {nil, %{}},
          {nil, nil}
        ] do
      Repo.query!("UPDATE users SET locked_at=$1, settings=$2 WHERE id=$3", [
        locked_at,
        settings,
        user.id
      ])

      if locked_at, do: assert(Accounts.get(user.id) == nil)

      for kind <- ~w(month digest), method <- [:get, :head] do
        conn =
          build_conn()
          |> assign(:now, @now)
          |> dispatch(@endpoint, method, "/shared/#{kind}/#{uuid}")

        assert conn.status == 200
        if method == :head, do: assert(conn.resp_body == "")
        refute conn.resp_body =~ "data-api-key"
      end
    end
  end

  @tag public_owner_absent: true
  test "public month and digest refuse a deleted or absent owner without crashing", %{
    user: user,
    uuid: uuid
  } do
    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=$2", [DateTime.to_naive(@now), user.id])

    for kind <- ~w(month digest) do
      conn = build_conn() |> assign(:now, @now) |> get("/shared/#{kind}/#{uuid}")
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    end

    assert Dawarich.Stats.Sharing.get(uuid, @now) == nil
    assert Dawarich.Digests.Sharing.get(uuid, @now) == nil
    assert Accounts.public_owner(-1) == nil
  end

  @tag public_card_owner_states: true
  test "public achievement page and image preserve NULL-settings and locked owner admission", %{
    user: user,
    uuid: uuid
  } do
    Dawarich.Test.SeedIds.insert_all!(Repo, "achievement_progresses", [
      %{
        user_id: user.id,
        achievement_key: "border_hopper",
        sharing_enabled: true,
        sharing_uuid: uuid,
        state: %{},
        created_at: DateTime.to_naive(@now),
        updated_at: DateTime.to_naive(@now)
      }
    ])

    for settings <- [%{}, nil] do
      Repo.query!("UPDATE users SET settings=$1, locked_at=$2 WHERE id=$3", [
        settings,
        DateTime.to_naive(DateTime.utc_now()),
        user.id
      ])

      assert {:ok, _} = Dawarich.Achievements.PublicCard.load(Repo, uuid, %{})

      assert {:ok, "synthetic-png"} =
               Dawarich.Achievements.OgImage.call(Repo, uuid, render: fn _ -> "synthetic-png" end)
    end

    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=$2", [DateTime.to_naive(@now), user.id])
    assert :not_found = Dawarich.Achievements.PublicCard.load(Repo, uuid, %{})
    assert :not_found = Dawarich.Achievements.OgImage.call(Repo, uuid)
  end
end
