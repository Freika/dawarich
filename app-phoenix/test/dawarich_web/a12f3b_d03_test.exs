defmodule DawarichWeb.A12f3bD03Test do
  use Dawarich.JobsCase
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias Dawarich.Admin.{UserSecurity, UserUpdate}
  alias DawarichWeb.{AdminWrites.Users, RailsCsrf}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    start_oban(AdminRecoveryOban)
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    for repo <- [Repo, ScratchRepo], {id, admin} <- [{33001, true}, {33002, false}] do
      RailsUser.insert!(
        %{
          id: id,
          email: "admin-user-#{id}@example.invalid",
          admin: admin,
          settings: %{"timezone" => "UTC", "locale" => "de"}
        },
        repo
      )
    end

    %{
      actor: Accounts.get(33001),
      context: %{
        repo: ScratchRepo,
        self_hosted: true,
        oidc: false,
        locale: "de",
        oban: AdminRecoveryOban,
        env: %{"SELF_HOSTED" => "true"}
      }
    }
  end

  @tag a12f3b_case: "D03a"
  test "admin user forms preserve last admin and native deletion producer", c do
    for params <- [%{"admin" => "0"}, %{"status" => "disabled"}] do
      assert {:blocked, _} = UserUpdate.call(c.actor, 33001, params, c.context)
    end

    assert Code.ensure_loaded?(DawarichWeb.AdminUserDestroy)

    enqueue = fn id ->
      ScratchRepo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'users.destroy',1,$1,'{}',$2,now())",
        [%{"user_id" => id}, id],
        log: false
      )

      :ok
    end

    rows(
      "INSERT INTO families(id,creator_id,name,created_at,updated_at) VALUES(33001,33002,'Synthetic family',now(),now())"
    )

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(33001,33002,0,now(),now()),(33001,33001,1,now(),now())"
    )

    context = Map.put(c.context, :enqueue_destroy, enqueue)
    refused = request(33001, "DELETE", "/settings/users/33002", []) |> apply_destroy(context)
    assert refused.status == 303
    assert rows("SELECT deleted_at FROM users WHERE id=33002") == [[nil]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    rows("DELETE FROM family_memberships WHERE user_id=33001")

    conn =
      request(33001, "POST", "/settings/users/33002", [{"_method", "delete"}])
      |> Users.call(action: :update, context: context)

    assert conn.status == 302
    assert rows("SELECT deleted_at IS NOT NULL FROM users WHERE id=33002") == [[true]]

    assert rows("SELECT command_type,payload FROM job_outbox") == [
             ["users.destroy", %{"user_id" => 33002}]
           ]

    conn = request(33001, "DELETE", "/settings/users/33002", []) |> apply_destroy(context)
    assert conn.status == 404
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
    conn = request(33002, "DELETE", "/settings/users/33001", []) |> apply_destroy(context)
    assert conn.status == 303
    assert rows("SELECT deleted_at IS NULL FROM users WHERE id=33001") == [[true]]

    conn =
      request(33001, "DELETE", "/settings/users/33001", [])
      |> apply_destroy(Map.put(c.context, :enqueue_destroy, fn _ -> {:error, :failed} end))

    assert conn.status == 503
    assert rows("SELECT deleted_at IS NULL FROM users WHERE id=33001") == [[true]]
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end

  @tag a12f3b_case: "D03b"
  test "admin password reset invokes native mail under correct locale", c do
    conn =
      request(33001, "POST", "/settings/users/33002/send_password_reset", [])
      |> Users.call(action: :reset, context: c.context)

    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/settings/users/33002"]
    assert [[digest]] = rows("SELECT reset_password_token FROM users WHERE id=33002")
    assert is_binary(digest)

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               inspect(Dawarich.Auth.Recovery.MailWorker)
             ])

    assert args["digest"] == digest
    assert args["locale"] == "de"
    assert args["user_id"] == 33002
    assert args["kind"] == "reset_password_instructions"
    refute Jason.encode!(args) =~ "reset_password_token"

    conn =
      request(33001, "POST", "/settings/users/33999/send_password_reset", [])
      |> Users.call(action: :reset, context: c.context)

    assert conn.status == 404
    assert {:handoff, :actor} = UserSecurity.reset(Accounts.get(33002), 33001, c.context)

    assert {:handoff, :cloud} =
             UserSecurity.reset(c.actor, 33001, %{c.context | self_hosted: false})

    assert rows("SELECT reset_password_token FROM users WHERE id=33001") == [[nil]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]

    assert {:terminal, :mail} =
             UserSecurity.reset(
               c.actor,
               33001,
               Map.put(c.context, :enqueue, fn _ -> {:error, :smtp} end)
             )

    assert rows("SELECT reset_password_token FROM users WHERE id=33001") == [[nil]]
  end

  @tag a12f3b_case: "D03c"
  test "standalone admin refusals preserve source status flash and no effects", c do
    for {actor, context} <- [{33002, c.context}, {33001, %{c.context | self_hosted: false}}] do
      conn =
        request(actor, "POST", "/settings/users", [
          {"user[email]", "refused@example.invalid"},
          {"user[password]", "synthetic-admin-password"}
        ])
        |> Users.call(action: :create, context: context)

      assert conn.status == 303
      assert get_resp_header(conn, "location") == ["http://www.example.com/"]
      assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"] != ""
    end

    assert rows("SELECT count(*) FROM users") == [[2]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  defp apply_destroy(conn, context),
    do: apply(DawarichWeb.AdminUserDestroy, :call, [conn, [context: context]])

  defp request(id, method, path, values) do
    session = RailsUser.session(id)
    raw = URI.encode_query([{"authenticity_token", RailsCsrf.masked_token(session)} | values])

    Plug.Test.conn(method, path, raw)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
  end
end
