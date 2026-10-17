defmodule Dawarich.Auth.Api.PayloadTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.{Account, Api.Actor, Api.Payload}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{Repo, Test.RailsUser}

  @rows "test/fixtures/auth/api_auth/login.json" |> File.read!() |> Jason.decode!()
  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @id 954_510
  @context %{self_hosted: true, oidc: false, timezone: "Etc/UTC"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: @id,
      email: "a11f-source@example.invalid",
      api_key: "runtime:api_key",
      encrypted_password: @source["login"]["user"]["encrypted_password"],
      subscription_source: 0,
      active_until: nil,
      settings: %{"timezone" => "UTC"}
    })

    :ok
  end

  test "API auth payload matches every admitted source subject without status gating" do
    for row <- @rows, row["response"]["status"] == 200 do
      state = hd(row["before"])

      changes =
        Map.new(~w(status plan subscription_source active_until locked_at), fn key ->
          value = state[key]
          value = if key in ~w(active_until locked_at) && value, do: datetime(value), else: value
          {String.to_existing_atom(key), value}
        end)

      seed(changes)
      before = snapshot()
      assert {:ok, user} = Actor.load(@id, @context)
      assert {:ok, by_email} = Actor.by_email(user.email, @context)
      assert by_email.id == @id

      context =
        Map.put(
          @context,
          :timezone,
          if(row["name"] == "active-offset", do: "Europe/Berlin", else: "Etc/UTC")
        )

      assert {:ok, term} = Payload.read(user, context)
      assert IO.iodata_to_binary(Ruby.json(term)) == row["response"]["body"], row["name"]
      assert snapshot() == before
    end

    seed(%{locked_at: nil, status: 3, plan: 0, subscription_source: 0, active_until: nil})
    assert {:ok, user} = Actor.load(@id, @context)
    assert {:ok, {:object, pairs}} = Payload.read(user, Map.put(@context, :caller_id, @id + 1))
    assert Map.new(pairs)["user_id"] == @id and Map.new(pairs)["effective_plan"] == "lite"

    for changes <- [
          %{status: 99},
          %{plan: 99},
          %{subscription_source: 99},
          %{provider: "openid_connect"},
          %{encrypted_password: "legacy"},
          %{settings: %{"maps" => %{"url" => "  https://example.invalid  "}}},
          %{deleted_at: ~U[2026-10-04 12:00:00.000000Z]}
        ] do
      original = Repo.get!(Account, @id)
      seed(changes)
      before = snapshot()
      assert {:replay, _} = Actor.load(@id, @context)
      assert snapshot() == before
      seed(Map.take(Map.from_struct(original), Map.keys(changes)))
    end

    assert {:replay, _} = Actor.load(@id, %{@context | self_hosted: false})
    assert {:replay, _} = Actor.load(@id, %{@context | oidc: true})
    assert {:replay, _} = Actor.load(@id + 1, @context)
    assert {:replay, _} = Actor.by_email("missing@example.invalid", @context)
  end

  defp datetime(text) do
    at = text |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
    %{at | microsecond: {elem(at.microsecond, 0), 6}}
  end

  defp snapshot,
    do: Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

  defp seed(changes),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(changes) |> Repo.update!(log: false)
end
