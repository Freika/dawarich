defmodule Dawarich.AfterCommitAccountCacheTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, TtlCache}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)

    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "after-commit-account@dawarich.test",
        api_key: "synthetic-after-commit-key",
        plan: 0
      })

    on_exit(fn -> TtlCache.delete({DawarichWeb.RateLimit, user.api_key}) end)
    %{user: user}
  end

  test "API key rotation rollback preserves the committed local plan cache", %{user: user} do
    TtlCache.put({DawarichWeb.RateLimit, user.api_key}, %{plan: 0}, 60_000)

    assert {:error, :cancel} =
             Dawarich.Transaction.run(Repo, fn ->
               assert {:ok, _} = Dawarich.Auth.ApiKeys.rotate_session(RailsUser.session(user.id))

               assert Repo.query!(
                        "SELECT count(*) FROM oban.oban_jobs WHERE args->>'operation'='rate_limit' AND args->'payload'->>'user_id'=$1",
                        [to_string(user.id)],
                        log: false
                      ).rows == [[1]]

               Repo.rollback(:cancel)
             end)

    assert TtlCache.lookup({DawarichWeb.RateLimit, user.api_key}) == {:ok, %{plan: 0}}
  end

  test "subscription rollback preserves Redis plan cache and cancels eviction intent", %{
    user: user
  } do
    key = "rack_attack/plan/" <> user.api_key
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "committed-plan"])

    claims = %{
      "user_id" => user.id,
      "event_id" => Ecto.UUID.generate(),
      "event_timestamp_ms" => 1,
      "exp" => System.os_time(:second) + 300,
      "plan" => "pro",
      "status" => "active",
      "subscription_source" => "paddle"
    }

    context = %{
      repo: Repo,
      env: %{
        "SUBSCRIPTION_WEBHOOK_SECRET" => "synthetic-after-commit-webhook",
        "JWT_SECRET_KEY" => "synthetic-after-commit-jwt"
      },
      native: true,
      self_hosted: false
    }

    header = Base.url_encode64(Jason.encode!(%{"alg" => "HS256"}), padding: false)
    payload = Base.url_encode64(Jason.encode!(claims), padding: false)

    signature =
      :crypto.mac(:hmac, :sha256, context.env["JWT_SECRET_KEY"], header <> "." <> payload)
      |> Base.url_encode64(padding: false)

    token = Enum.join([header, payload, signature], ".")

    assert {:error, :cancel} =
             Dawarich.Transaction.run(Repo, fn ->
               assert {:message, 200, _} =
                        Dawarich.Subscriptions.Callback.call(
                          token,
                          "synthetic-after-commit-webhook",
                          context
                        )

               assert Repo.query!(
                        "SELECT count(*) FROM oban.oban_jobs WHERE args->>'operation'='subscription' AND args->'payload'->>'user_id'=$1",
                        [to_string(user.id)],
                        log: false
                      ).rows == [[1]]

               Repo.rollback(:cancel)
             end)

    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "committed-plan"}
  end
end
