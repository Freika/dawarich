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

  @tag :a12f2_a_04
  test "Notes Cloud CRUD preserves own scope Ruby parameter shapes uniqueness and source failures",
       %{user: user, now: now} do
    System.put_env("SELF_HOSTED", "false")
    missing = invoke(DawarichWeb.Api.NotesController, :create, user, %{}, now)
    assert missing.status == 400

    attrs = %{
      "body" => "Synthetic note",
      "title" => "Day",
      "noted_at" => "2026-10-06",
      "latitude" => 0,
      "longitude" => 0,
      "ignored" => true
    }

    created = invoke(DawarichWeb.Api.NotesController, :create, user, %{"note" => attrs}, now)
    assert created.status == 201
    body = Jason.decode!(created.resp_body)
    assert body["date"] == source_body("notes", "date_only")["date"]
    assert body["latitude"] == 0.0
    id = body["id"]
    Repo.query!("UPDATE notes SET source_digest='synthetic-digest' WHERE id=$1", [id])
    foreign = user()

    assert invoke(DawarichWeb.Api.NotesController, :show, foreign, %{"id" => to_string(id)}, now).status ==
             404

    assert invoke(
             DawarichWeb.Api.NotesController,
             :update,
             foreign,
             %{"id" => to_string(id), "note" => %{"body" => "Foreign"}},
             now
           ).status == 404

    updated =
      invoke(
        DawarichWeb.Api.NotesController,
        :update,
        user,
        %{"id" => to_string(id), "note" => %{"body" => "Updated", "latitude" => nil}},
        now
      )

    assert updated.status == 200
    assert Jason.decode!(updated.resp_body)["latitude"] == 0.0

    assert Repo.query!("SELECT source_digest FROM notes WHERE id=$1", [id]).rows == [
             ["synthetic-digest"]
           ]

    invalid =
      invoke(
        DawarichWeb.Api.NotesController,
        :create,
        user,
        %{"note" => %{"body" => "", "noted_at" => "invalid"}},
        now
      )

    assert invalid.status == 422

    assert Jason.decode!(invalid.resp_body)["errors"] ==
             source_body("notes", "invalid_date")["errors"]

    assert invoke(DawarichWeb.Api.NotesController, :index, user, %{}, now).status == 200

    assert invoke(
             DawarichWeb.Api.NotesController,
             :destroy,
             foreign,
             %{"id" => to_string(id)},
             now
           ).status == 404

    assert invoke(DawarichWeb.Api.NotesController, :destroy, user, %{"id" => to_string(id)}, now).status ==
             200
  end

  @tag :a12f2_a_05
  test "Visits Cloud operations match source bbox times soft deletion and per item commit boundaries",
       %{user: user, now: now} do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    System.put_env("SELF_HOSTED", "false")

    attrs = %{
      "name" => "Synthetic visit",
      "latitude" => 52.52,
      "longitude" => 13.4,
      "started_at" => "2026-10-06T10:00:00Z",
      "ended_at" => "2026-10-06T11:00:00Z",
      "status" => "confirmed",
      "place_id" => -1,
      "area_id" => -1
    }

    result =
      invoke(
        DawarichWeb.Api.VisitsController,
        :batch,
        user,
        %{"visits" => [attrs, Map.put(attrs, "status", "invalid")]},
        now
      )

    assert result.status == 200
    body = Jason.decode!(result.resp_body)
    assert body["created_count"] == 1
    assert body["failed_count"] == 1
    id = hd(body["results"])["visit"]["id"]
    assert Repo.query!("SELECT count(*) FROM visits WHERE user_id=$1", [user.id]).rows == [[1]]

    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [
             "Dawarich.Points.VisitMonthsWorker"
           ]).rows == [[1]]

    assert Repo.query!(
             "SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'user_id'=$1::bigint::text",
             [user.id]
           ).rows == [[0]]

    foreign = user()

    assert invoke(DawarichWeb.Api.VisitsController, :show, foreign, %{"id" => to_string(id)}, now).status ==
             404

    assert invoke(DawarichWeb.Api.VisitsController, :show, user, %{"id" => to_string(id)}, now).status ==
             200

    user = %{user | plan: 0}
    Repo.query!("UPDATE visits SET started_at=$2 WHERE id=$1", [id, ~N[2020-01-01 00:00:00]])

    assert invoke(DawarichWeb.Api.VisitsController, :show, user, %{"id" => to_string(id)}, now).status ==
             404

    Repo.query!("UPDATE visits SET started_at=$2 WHERE id=$1", [id, ~N[2026-10-06 10:00:00]])

    assert invoke(DawarichWeb.Api.VisitsController, :destroy, user, %{"id" => to_string(id)}, now).status ==
             204

    assert invoke(DawarichWeb.Api.VisitsController, :show, user, %{"id" => to_string(id)}, now).status ==
             404

    assert Repo.query!("SELECT deleted_at IS NOT NULL FROM visits WHERE id=$1", [id]).rows == [
             [true]
           ]
  end

  @tag :a12f2_a_06
  test "Family Cloud APIs preserve inherited entitlement consent cooldown and membership scope",
       %{user: user, now: now} do
    System.put_env("SELF_HOSTED", "false")
    id = family(user, now)
    Repo.query!("UPDATE families SET access_until=$2 WHERE id=$1", [id, ~N[2000-01-01 00:00:00]])
    mine = invoke(DawarichWeb.Api.FamilyController, :mine, %{user | plan: 0}, %{}, now)
    assert mine.status == 200

    assert Jason.decode!(mine.resp_body) == %{
             "lapsed" => true,
             "family" => %{"name" => "Synthetic"},
             "me" => %{"user_id" => user.id, "owner" => true}
           }

    assert invoke(DawarichWeb.Api.FamilyController, :locations, %{user | plan: 0}, %{}, now).status ==
             403

    Repo.query!("UPDATE families SET access_until=$2 WHERE id=$1", [id, ~N[3026-01-01 00:00:00]])
    member = user()

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,NOW(),NOW())",
      [id, member.id]
    )

    settings = %{
      "family" => %{
        "location_sharing" => %{
          "enabled" => true,
          "duration" => "permanent",
          "started_at" => "2026-10-06T12:00:00Z",
          "share_history" => true,
          "history_window" => "7d",
          "history_before_sharing" => false
        }
      }
    }

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [member.id, settings])

    for at <- [DateTime.add(now, -3600), DateTime.add(now, 1800)] do
      Repo.query!(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,ST_SetSRID(ST_MakePoint(13,52),4326),NOW(),NOW())",
        [member.id, DateTime.to_unix(at)]
      )
    end

    history =
      invoke(
        DawarichWeb.Api.FamilyController,
        :history,
        %{user | plan: 0},
        %{"start_at" => "2026-10-06T10:00:00Z", "end_at" => "2026-10-06T13:00:00Z"},
        now
      )

    assert history.status == 200
    assert [%{"points" => [[52.0, 13.0, stamp]]}] = Jason.decode!(history.resp_body)["members"]
    assert stamp == DateTime.to_unix(DateTime.add(now, 1800))

    assert invoke(
             DawarichWeb.Api.FamilyController,
             :history,
             user,
             %{"start_at" => "bad", "end_at" => "bad"},
             now
           ).status == 400

    outsider = user()

    assert invoke(DawarichWeb.Api.FamilyController, :mine, %{outsider | plan: 0}, %{}, now).status ==
             403
  end

  @tag :a12f2_a_07
  test "Shared APIs retain phrase grant privacy photo ACL and resource failures without API authentication",
       %{user: user, now: now} do
    link_id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,name,resource_type,settings,created_at,updated_at) VALUES($1::text::uuid,$2,'Synthetic',2,$3,NOW(),NOW())",
      [
        link_id,
        user.id,
        %{"start_date" => "2026-10-06", "end_date" => "2026-10-06", "show_photos" => true}
      ]
    )

    params = %{"id" => link_id}

    photos =
      invoke(DawarichWeb.Api.SharedController, :photos, nil, params, now, [
        {"x-dawarich-client", "ios"}
      ])

    assert photos.status == 200
    assert Jason.decode!(photos.resp_body) == []
    link = Dawarich.SharedLinks.active(link_id, now)
    key = Dawarich.SharedApi.Closure.photo_ids_key(link)
    Dawarich.Photos.ProviderCache.put(key, %{"immich:public-photo" => true}, 600)
    assert Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "public-photo")
    refute Dawarich.SharedApi.Closure.allowed_photo?(link, "immich", "private-photo")

    private =
      invoke(
        DawarichWeb.Api.SharedController,
        :thumbnail,
        nil,
        Map.merge(params, %{"photo_id" => "private-photo", "source" => "immich"}),
        now
      )

    assert private.status == 404
    server = Dawarich.Test.RawHTTP.listen()
    image = <<255, 216, 0, 255, 217>>

    task =
      Task.async(fn ->
        asset = %{
          "id" => "public-photo",
          "type" => "IMAGE",
          "fileCreatedAt" => "2026-10-06T12:00:00Z",
          "localDateTime" => "2026-10-06T12:00:00",
          "originalFileName" => "synthetic.jpg",
          "exifInfo" => %{"latitude" => 52.0, "longitude" => 13.0}
        }

        replies = [
          {"POST /api/search/metadata HTTP/1.1", "application/json",
           Jason.encode!(%{"assets" => %{"items" => [asset]}})},
          {"POST /api/search/metadata HTTP/1.1", "application/json",
           Jason.encode!(%{"assets" => %{"items" => []}})},
          {"GET /api/assets/public-photo/thumbnail?size=preview HTTP/1.1", "image/jpeg", image}
        ]

        for {line, type, body} <- replies do
          socket = Dawarich.Test.RawHTTP.accept(server)
          {head, rest} = Dawarich.Test.RawHTTP.read_head(socket)
          assert Dawarich.Test.RawHTTP.request_line(head) == line
          size = head |> Dawarich.Test.RawHTTP.header("content-length") |> List.first() || "0"
          Dawarich.Test.RawHTTP.read_at_least(socket, rest, String.to_integer(size))

          Dawarich.Test.RawHTTP.reply(socket, [
            "HTTP/1.1 200 OK\r\nconnection: close\r\ncontent-type: #{type}\r\ncontent-length: #{byte_size(body)}\r\n\r\n",
            body
          ])

          :gen_tcp.close(socket)
        end
      end)

    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [
      user.id,
      %{
        "timezone" => "UTC",
        "immich_url" => "http://127.0.0.1:#{server.port}",
        "immich_api_key" => "synthetic-photo-key"
      }
    ])

    photos = invoke(DawarichWeb.Api.SharedController, :photos, nil, params, now)
    assert [%{"id" => "public-photo", "thumbnail_url" => url}] = Jason.decode!(photos.resp_body)
    assert url == "/api/v1/shared/#{link_id}/photos/public-photo/thumbnail?source=immich"
    assert get_resp_header(photos, "cache-control") == ["max-age=60, public"]

    thumbnail =
      invoke(
        DawarichWeb.Api.SharedController,
        :thumbnail,
        nil,
        Map.merge(params, %{"photo_id" => "public-photo", "source" => "immich"}),
        now
      )

    assert thumbnail.status == 200
    assert thumbnail.resp_body == image
    Task.await(task)
    Dawarich.Photos.ProviderCache.invalidate(user.id)

    Repo.query!(
      "UPDATE shared_links SET magic_phrase='synthetic-phrase' WHERE id=$1::text::uuid",
      [link_id]
    )

    assert invoke(DawarichWeb.Api.SharedController, :points, nil, params, now).status == 401
    Repo.query!("UPDATE shared_links SET revoked_at=NOW() WHERE id=$1::text::uuid", [link_id])
    assert invoke(DawarichWeb.Api.SharedController, :photos, nil, params, now).status == 404
    Redis.cache_command(["UNLINK", key])
  end

  defp source_body(section, name) do
    fixture = "test/fixtures/a12f2a/closure.json" |> File.read!() |> Jason.decode!()
    Enum.find(fixture[section], &(&1["name"] == name))["response"]["body"] |> Jason.decode!()
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
