defmodule Dawarich.MapsTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{Accounts, Maps, Repo}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    row =
      RailsUser.insert!(%{
        id: 96001,
        email: "native-map@dawarich.test",
        api_key: "synthetic-map-key",
        settings: %{"timezone" => "Europe/Berlin", "immich_api_key" => "synthetic-provider-key"}
      })

    %{scope: Maps.principal(Accounts.get(row.id), "en"), id: row.id}
  end

  test "native map principal interoperates with M4 and retains its revoked identity", %{
    scope: scope,
    id: id
  } do
    assert {:ok, admitted} = Dawarich.Accounts.NativeAccess.admit(scope)
    assert %Dawarich.Accounts.Principal{} = admitted.user

    Repo.query!(
      "UPDATE users SET encrypted_password=$1 WHERE id=$2",
      [String.duplicate("revoked", 10), id],
      log: false
    )

    assert {:error, :stale_session} = Dawarich.Accounts.NativeAccess.admit(scope)
    assert {:error, :stale_session} = Maps.admit(admitted)
  end

  test "map read projection omits credentials and bulk geometry", %{scope: scope} do
    assert {:ok, page} =
             Maps.page(scope, %{},
               now: ~U[2026-10-10 10:00:00Z],
               self_hosted: true,
               family: false,
               env: %{}
             )

    serialized = inspect({scope, page}, limit: :infinity)
    refute serialized =~ "synthetic-map-key"
    refute serialized =~ "synthetic-provider-key"
    refute Map.has_key?(page, :api_key)
    refute Map.has_key?(page, :points)
    refute Map.has_key?(page, :tracks)
    assert page.window.zone == "Europe/Berlin"
  end

  test "revoked map session cannot issue a command or accept a late result", %{
    scope: scope,
    id: id
  } do
    assert {:ok, fresh} = Maps.admit(scope)

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      id
    ])

    for original <- [scope, fresh] do
      assert {:error, :stale_session} = Maps.admit(original)

      assert {:error, :stale_session} =
               Maps.with_actor(original, fn _ -> flunk("effect accepted") end)
    end
  end

  test "missing place is a typed refusal without a redirect loop", %{scope: scope} do
    assert {:error, :not_found} =
             Maps.page(scope, %{"place_id" => "987654321"},
               now: DateTime.utc_now(),
               self_hosted: true,
               family: false,
               env: %{}
             )
  end

  test "inactive locked deleted and pending actors lose map admission", %{scope: scope, id: id} do
    for status <- [0, 3] do
      Repo.query!("UPDATE users SET status = $1 WHERE id = $2", [status, id])
      assert {:error, :unauthorized} = Maps.admit(scope)
    end

    Repo.query!("UPDATE users SET status = 1, locked_at = now() WHERE id = $1", [id])
    assert {:error, :stale_session} = Maps.admit(scope)
    Repo.query!("UPDATE users SET locked_at = NULL, deleted_at = now() WHERE id = $1", [id])
    assert {:error, :stale_session} = Maps.admit(scope)
  end
end
