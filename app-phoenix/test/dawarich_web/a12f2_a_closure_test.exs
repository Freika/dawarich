defmodule DawarichWeb.A12f2AClosureTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.{Repo, Redis}
  alias DawarichWeb.Api.{PlanController, UsersController}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    env = %{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "JWT_SECRET_KEY" => "test",
      "MANAGER_URL" => "https://manager.example.invalid"
    }

    previous = Map.new(env, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(env, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    start_supervised!(hd(Redis.child_specs()))
    start_supervised!(hd(Redis.cache_child_specs()))
    {:ok, user: user(), now: ~U[2026-10-06 12:00:00Z]}
  end

  @tag :a12f2_a_02
  test "Cloud plan and me retain source settings enums subscription features and pending payment behavior",
       %{user: user, now: now} do
    for mode <- [nil, "true", "false"] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")
      lite = %{user | plan: 0}
      plan = invoke(PlanController, :show, lite, %{}, now)
      assert plan.status == 200
      body = Jason.decode!(plan.resp_body)
      assert body["effective_plan"] == "lite"
      assert body["features"]["heatmap"] == (mode != "false")
      assert body["features"]["write_api"] == if(mode == "false", do: "create_only", else: true)
    end

    Repo.query!("UPDATE users SET plan=0,settings=$2 WHERE id=$1", [
      user.id,
      %{
        "timezone" => "Berlin",
        "maps" => %{"hidden_tile_categories" => ["water"], "distance_unit" => "mi"}
      }
    ])

    me = invoke(UsersController, :me, %{user | plan: 0, status: 0}, %{}, now)
    assert me.status == 200
    body = Jason.decode!(me.resp_body)
    assert body["subscription"]["plan"] == "lite"
    assert body["features"]["family"] == false
    assert body["user"]["settings"]["globe_projection"] == false
    refute Map.has_key?(body["user"]["settings"]["maps"], "hidden_tile_categories")

    cached =
      invoke(UsersController, :me, %{user | plan: 0}, %{}, now, [
        {"if-none-match", hd(get_resp_header(me, "etag"))}
      ])

    assert cached.status == 304
    pending = invoke(UsersController, :me, %{user | status: 3}, %{}, now)
    assert pending.status == 402

    assert Jason.decode!(pending.resp_body)["resume_url"] =~
             "https://manager.example.invalid/auth/dawarich?token="

    family(user, now)

    inherited =
      invoke(PlanController, :show, %{user | plan: 0}, %{}, now)
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    assert inherited["effective_plan"] == "family"
    assert inherited["features"]["sharing"] == true
    assert invoke(PlanController, :show, %{user | plan: 9}, %{}, now).status == 500
  end

  @tag :a12f2_a_03
  test "Manager exist retains secret refusal id coercion tombstones and anonymous headers in Cloud",
       %{user: user, now: now} do
    previous = System.get_env("SUBSCRIPTION_WEBHOOK_SECRET")

    on_exit(fn ->
      if previous,
        do: System.put_env("SUBSCRIPTION_WEBHOOK_SECRET", previous),
        else: System.delete_env("SUBSCRIPTION_WEBHOOK_SECRET")
    end)

    System.put_env("SELF_HOSTED", "false")
    System.delete_env("SUBSCRIPTION_WEBHOOK_SECRET")
    assert invoke(UsersController, :exist, nil, %{}, now).status == 503
    System.put_env("SUBSCRIPTION_WEBHOOK_SECRET", "synthetic-a12f2a-webhook")
    mobile = [{"x-dawarich-client", "ios"}, {"x-webhook-secret", "wrong"}]
    bad = invoke(UsersController, :exist, nil, %{}, now, mobile)
    assert bad.status == 401
    assert Jason.decode!(bad.resp_body) == oracle("closure_manager_bad_secret")
    assert get_resp_header(bad, "x-dawarich-response") == ["Hey, I'm alive!"]
    valid = [{"x-webhook-secret", "synthetic-a12f2a-webhook"}]
    assert invoke(UsersController, :exist, nil, %{}, now, valid).status == 422
    deleted = user()
    Repo.query!("UPDATE users SET deleted_at=NOW() WHERE id=$1", [deleted.id])

    params = %{
      "ids" => [
        " #{user.id} ",
        user.id,
        "1_2",
        "bad",
        "12x",
        deleted.id,
        %{"id" => user.id},
        12.0,
        true,
        nil
      ]
    }

    result = invoke(UsersController, :exist, nil, params, now, valid)
    assert result.status == 200

    assert Jason.decode!(result.resp_body) == %{
             "existing" => [user.id],
             "missing" => [12, deleted.id]
           }

    assert invoke(UsersController, :exist, nil, %{"ids" => %{"x" => 1}}, now, valid).status == 200
  end

  defp oracle(name) do
    fixture = "test/fixtures/a12f2a/closure.json" |> File.read!() |> Jason.decode!()
    Enum.find(fixture["cases"], &(&1["name"] == name))["response"]["body"] |> Jason.decode!()
  end

  defp invoke(module, action, user, params, now, headers \\ []) do
    conn = Plug.Test.conn("GET", "/api/v1/plan")

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    conn = %{conn | path_params: Map.take(params, ~w(id photo_id))}

    conn
    |> assign(:api_user, user)
    |> assign(:api_params, params)
    |> assign(:api_now, now)
    |> assign(:api_format, :json)
    |> assign(:api_tag, "api")
    |> assign(:api_started, System.monotonic_time())
    |> assign(:api_headers, [])
    |> assign(:api_vary, false)
    |> assign(:api_request_id, "test")
    |> assign(:api_if_none_match, List.first(get_req_header(conn, "if-none-match"), ""))
    |> module.call(action)
  end

  defp user do
    email = "synthetic-#{Ecto.UUID.generate()}@example.invalid"

    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,settings,status,plan,subscription_source,created_at,updated_at) VALUES($1,'','{}',1,1,0,NOW(),NOW()) RETURNING id",
        [email]
      ).rows

    %{
      id: id,
      email: email,
      plan: 1,
      status: 1,
      subscription_source: 0,
      timezone: "Etc/UTC",
      active_until: nil
    }
  end

  defp family(user, now) do
    [[id]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,access_until,created_at,updated_at) VALUES('Synthetic',$1,$2,NOW(),NOW()) RETURNING id",
        [user.id, DateTime.to_naive(DateTime.add(now, 86400))]
      ).rows

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,NOW(),NOW())",
      [id, user.id]
    )

    id
  end
end
