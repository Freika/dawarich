defmodule DawarichWeb.StandaloneApiGapsCommitTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "api-gap-commit-#{Ecto.UUID.generate()}@example.invalid",
        api_key: Ecto.UUID.generate(),
        settings: %{"timezone" => "UTC"}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      if user = Accounts.get(actor.id), do: Dawarich.DemoData.Destroyer.call(Repo, user)

      for table <- ~w(stats digests areas imports) do
        Repo.query!("DELETE FROM #{table} WHERE user_id=$1", [actor.id], log: false)
      end

      Repo.query!(
        "DELETE FROM oban.oban_jobs WHERE args->>'user_id'=$1 OR args->'payload'->>'user_id'=$1",
        [to_string(actor.id)],
        log: false
      )

      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    %{actor: actor}
  end

  @tag :gap_commit
  test "standalone API requests commit exactly one durable job from idle connections", %{
    actor: actor
  } do
    refute Repo.in_transaction?()

    Repo.query!(
      "INSERT INTO stats(user_id,year,month,distance,created_at,updated_at) VALUES($1,2024,1,0,now(),now())",
      [actor.id],
      log: false
    )

    conn = request(actor, :post, "/api/v1/digests", %{"year" => 2024})
    assert conn.status == 202
    refute Repo.in_transaction?()

    assert Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Digests.YearlyWorker' AND args->>'user_id'=$1",
             [to_string(actor.id)],
             log: false
           ).rows == [[1]]

    assert request(actor, :post, "/api/v1/digests", %{"year" => 1969}).status == 422

    assert Repo.query!(
             "SELECT count(*) FROM oban.oban_jobs WHERE args->>'user_id'=$1",
             [to_string(actor.id)],
             log: false
           ).rows == [[1]]

    Repo.query!(
      "INSERT INTO digests(user_id,year,period_type,created_at,updated_at) VALUES($1,2024,1,now(),now())",
      [actor.id],
      log: false
    )

    assert request(actor, :delete, "/api/v1/digests/2024").status == 204

    assert Repo.query!("SELECT id FROM digests WHERE user_id=$1", [actor.id], log: false).rows ==
             []

    Repo.query!(
      "INSERT INTO imports(user_id,name,source,status,demo,created_at,updated_at) VALUES($1,'Synthetic',6,2,true,now(),now())",
      [actor.id],
      log: false
    )

    assert request(actor, :delete, "/api/v1/demo_data").status == 200

    assert Repo.query!("SELECT id FROM imports WHERE user_id=$1", [actor.id], log: false).rows ==
             []

    [[id]] =
      Repo.query!(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
        [actor.id],
        log: false
      ).rows

    assert request(actor, :delete, "/api/v1/areas/#{id}").status == 200
    assert Repo.query!("SELECT id FROM areas WHERE user_id=$1", [actor.id], log: false).rows == []
    refute Repo.in_transaction?()
  end

  defp request(actor, method, path, params \\ %{}) do
    body = Jason.encode!(params)

    Plug.Test.conn(method, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> actor.api_key)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end
end
