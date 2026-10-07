defmodule DawarichWeb.StandaloneDigestResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Test.RailsUser

  @tag :review_digest_response
  test "digest remains durable after failed response preparation on an idle connection" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "review-idle-#{Ecto.UUID.generate()}@example.invalid",
        settings: %{}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      Repo.query!("DELETE FROM digests WHERE user_id=$1", [actor.id], log: false)
      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)
    end)

    [[digest]] =
      Repo.query!(
        "INSERT INTO digests(user_id,year,period_type,created_at,updated_at) VALUES($1,2024,1,now(),now()) RETURNING id",
        [actor.id],
        log: false
      ).rows

    refute Repo.in_transaction?()

    conn =
      Plug.Test.conn(:delete, "/api/v1/digests/2024")
      |> DawarichWeb.Api.Respond.prepare()
      |> assign(:api_user, Accounts.get(actor.id))
      |> assign(:api_headers, [{"x-review", "\n"}])
      |> Map.put(:path_params, %{"year" => "2024"})

    assert_raise Plug.Conn.InvalidHeaderError, fn ->
      DawarichWeb.Api.DigestWritesController.call(conn, :destroy)
    end

    refute Repo.in_transaction?()
    rows = Repo.query!("SELECT id FROM digests WHERE id=$1", [digest], log: false).rows
    assert rows == [[digest]]
  end
end
