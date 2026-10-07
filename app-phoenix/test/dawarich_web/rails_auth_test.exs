defmodule DawarichWeb.RailsAuthTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test
  require Ecto.Query

  alias Dawarich.{Accounts, Repo}
  alias DawarichWeb.{RailsAuth, RailsCsrf, SessionStore}

  @fixture "test/fixtures/rails_cookies.json" |> File.read!() |> Jason.decode!()
  @now @fixture["now"] |> DateTime.from_iso8601() |> elem(1)
  @user @fixture["user"]
  @salt String.slice(@user["encrypted_password"], 0, 29)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("users", [
      %{
        id: @user["id"],
        email: @user["email"],
        encrypted_password: @user["encrypted_password"],
        remember_created_at: naive(@user["remember_created_at"]),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    :ok
  end

  defp naive(iso), do: iso |> NaiveDateTime.from_iso8601!()

  defp update_user(fields), do: Repo.update_all(from_users(), set: fields)
  defp from_users, do: Ecto.Query.from(u in "users", where: u.id == ^@user["id"])

  defp conn_with(cookies) do
    Enum.reduce(cookies, conn(:get, "/"), fn {name, value}, conn ->
      put_req_cookie(conn, name, value)
    end)
  end

  defp current_user(cookies, now \\ @now),
    do: RailsAuth.call(conn_with(cookies), RailsAuth.init(now: now)).assigns.current_user

  defp session_cookie, do: [{"_dawarich_session", @fixture["session_cookie"]}]
  defp remember_cookie, do: [{"remember_user_token", @fixture["remember_cookie"]}]
  defp remember_payload, do: @fixture["expected_remember"]
  defp other_remember_cookie, do: [{"remember_user_token", @fixture["other_remember_cookie"]}]

  defp insert_other_user do
    other = @fixture["other_user"]
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("users", [
      %{
        id: other["id"],
        email: other["email"],
        encrypted_password: other["encrypted_password"],
        remember_created_at: naive(other["remember_created_at"]),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    other["id"]
  end

  defp csrf_session do
    {:ok, session} =
      Dawarich.RailsCookies.decrypt(
        @fixture["csrf"]["session_cookie"],
        "_dawarich_session",
        @fixture["rails_test_secret"],
        @now
      )

    session
  end

  test "the user in the Rails session is the current user" do
    assert %{id: id} = current_user(session_cookie())
    assert id == @user["id"]
  end

  test "session_user/2 reads only the Warden session, never the remember cookie" do
    assert %{id: id} = RailsAuth.session_user(conn_with(session_cookie()), now: @now)
    assert id == @user["id"]
    assert RailsAuth.session_user(conn_with(remember_cookie()), now: @now) == nil
    update_user(locked_at: NaiveDateTime.add(naive(@fixture["now"]), -60))
    assert {:locked, _} = RailsAuth.session_user(conn_with(session_cookie()), now: @now)
  end

  test "the decrypted Rails session is available to later plugs" do
    conn = conn(:get, "/") |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])

    assert RailsAuth.call(conn, RailsAuth.init(now: @now)).assigns.rails_session ==
             @fixture["expected_session"]
  end

  test "a password change ends the Rails session" do
    update_user(encrypted_password: "$2a$12$" <> String.duplicate("z", 53))
    assert current_user(session_cookie()) == nil
  end

  test "a soft-deleted user is nobody" do
    update_user(deleted_at: NaiveDateTime.utc_now())
    assert current_user(session_cookie()) == nil
    assert current_user(remember_cookie()) == nil
  end

  test "a locked user is nobody until the lock is an hour old" do
    update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())
    assert current_user(session_cookie()) == nil

    update_user(locked_at: @now |> DateTime.add(-61 * 60) |> DateTime.to_naive())
    assert %{} = current_user(session_cookie())
  end

  test "the remember-me cookie signs the user in without a session" do
    assert %{id: id} = current_user(remember_cookie())
    assert id == @user["id"]
  end

  test "remember-me ends after two weeks, after sign-out, and for a newer remember date" do
    assert current_user(remember_cookie(), DateTime.add(@now, 15 * 24 * 3600)) == nil

    update_user(remember_created_at: nil)
    assert current_user(remember_cookie()) == nil

    update_user(remember_created_at: @now |> DateTime.add(60) |> DateTime.to_naive())
    assert current_user(remember_cookie()) == nil
  end

  test "Devise's remember window is the one Rails uses" do
    assert Accounts.remember_for() == @fixture["remember_for_seconds"]
  end

  test "without the Rails secret nobody is signed in" do
    conn = conn(:get, "/") |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])

    assert RailsAuth.call(conn, RailsAuth.init(secret: nil, now: @now)).assigns.current_user ==
             nil
  end

  test "the LiveView session store derives the Rails user at every read and never stores it" do
    conn =
      conn(:get, "/")
      |> Map.put(:secret_key_base, String.duplicate("s", 64))
      |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])
      |> Plug.Conn.fetch_cookies()

    opts =
      SessionStore.init(
        DawarichWeb.Endpoint.session_options()
        |> Keyword.delete(:store)
        |> Keyword.delete(:key)
      )

    cookie = SessionStore.put(conn, nil, %{"a" => 1, "rails_user_id" => 999}, opts)

    assert {_sid, %{"a" => 1, "rails_user_id" => id}} = SessionStore.get(conn, cookie, opts)
    assert id == @user["id"]
    anonymous = conn |> Map.put(:req_cookies, %{}) |> Map.put(:cookies, %{})

    assert {_sid, %{"a" => 1, "rails_user_id" => nil}} =
             SessionStore.get(anonymous, cookie, opts)
  end

  test "the Rails CSRF token Phoenix renders passes Rails' own check, as Rails' token does" do
    {:ok, session} =
      Dawarich.RailsCookies.decrypt(
        @fixture["csrf"]["session_cookie"],
        "_dawarich_session",
        @fixture["rails_test_secret"],
        @now
      )

    assert RailsCsrf.valid?(session, @fixture["csrf"]["masked_token"])
    token = RailsCsrf.masked_token(session)
    assert RailsCsrf.valid?(session, token)
    refute token == RailsCsrf.masked_token(session)
    refute RailsCsrf.valid?(session, String.reverse(token))
    assert RailsCsrf.masked_token(%{}) == nil
  end

  describe "refusals and secrecy" do
    test "a locked account's session signs nobody in, even beside another account's remember cookie" do
      other_id = insert_other_user()
      assert %{id: ^other_id} = current_user(other_remember_cookie())

      update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())
      assert current_user(session_cookie() ++ other_remember_cookie()) == nil
    end

    test "a locked session user comes back tagged, never as a bare user" do
      id = @user["id"]
      update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())

      assert {:locked, %Dawarich.Accounts.User{id: ^id}} =
               Accounts.from_session(%{"warden.user.user.key" => [[id], @salt]}, @now)
    end

    test "a locked account's remember cookie signs nobody in until the lock is an hour old" do
      update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())
      assert current_user(remember_cookie()) == nil

      update_user(locked_at: @now |> DateTime.add(-61 * 60) |> DateTime.to_naive())
      assert %{} = current_user(remember_cookie())
    end

    test "a locked account is told apart from a visitor by where Rails would have found it" do
      locked = fn cookies ->
        conn =
          Enum.reduce(cookies, conn(:get, "/"), fn {name, value}, conn ->
            put_req_cookie(conn, name, value)
          end)

        RailsAuth.call(conn, RailsAuth.init(now: @now)).assigns.rails_locked
      end

      assert locked.(session_cookie()) == nil
      update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())
      assert locked.(session_cookie()) == :session
      assert locked.(remember_cookie()) == :cookie
      assert locked.([]) == nil
    end

    test "a session Rails cannot resolve falls through to the remember cookie, as Warden does" do
      other_id = insert_other_user()

      update_user(encrypted_password: "$2a$12$" <> String.duplicate("z", 53))
      assert %{id: ^other_id} = current_user(session_cookie() ++ other_remember_cookie())

      update_user(locked_at: @now |> DateTime.add(-30 * 60) |> DateTime.to_naive())
      assert %{id: ^other_id} = current_user(session_cookie() ++ other_remember_cookie())

      update_user(deleted_at: NaiveDateTime.utc_now(), locked_at: NaiveDateTime.utc_now())
      assert %{id: ^other_id} = current_user(session_cookie() ++ other_remember_cookie())
    end

    test "a lock expires after Devise's unlock_in, because Devise unlocks by time" do
      assert @fixture["lockable"]
      assert @fixture["time_unlock"]
      assert Accounts.unlock_in() == @fixture["unlock_in_seconds"]
    end

    test "a session whose salt is not the user's is nobody" do
      assert Accounts.from_session(%{"warden.user.user.key" => [[@user["id"]], @salt]}, @now)

      wrong = binary_part(@salt, 0, 28) <> if(String.ends_with?(@salt, "a"), do: "b", else: "a")
      refute Accounts.from_session(%{"warden.user.user.key" => [[@user["id"]], wrong]}, @now)
      refute Accounts.from_session(%{"warden.user.user.key" => [[@user["id"]], nil]}, @now)
      refute Accounts.from_session(%{"warden.user.user.key" => [[@user["id"]], [@salt]]}, @now)
    end

    test "a remember token that is not the user's own is refused" do
      [[id], token, generated_at] = remember_payload()
      assert Accounts.from_remember_cookie([[id], token, generated_at], @now)

      other_id = id + 1000
      other_password = "$2a$04$" <> String.duplicate("q", 53)
      stamp = NaiveDateTime.utc_now()

      Repo.insert_all("users", [
        %{
          id: other_id,
          email: "other-" <> @user["email"],
          encrypted_password: other_password,
          remember_created_at: naive(@user["remember_created_at"]),
          created_at: stamp,
          updated_at: stamp
        }
      ])

      refute Accounts.from_remember_cookie([[other_id], token, generated_at], @now)

      refute Accounts.from_remember_cookie(
               [[id], String.slice(other_password, 0, 29), generated_at],
               @now
             )

      refute Accounts.from_remember_cookie([[id], String.reverse(token), generated_at], @now)
    end

    test "remember-me ends two weeks after the token was issued, whatever the cookie's own expiry" do
      window = @fixture["remember_for_seconds"]
      assert Accounts.from_remember_cookie(remember_payload(), DateTime.add(@now, window - 1))
      refute Accounts.from_remember_cookie(remember_payload(), DateTime.add(@now, window))
    end

    test "an empty remember token is refused, even for a user with no password" do
      [[id], _token, generated_at] = remember_payload()
      update_user(encrypted_password: "")
      refute Accounts.from_remember_cookie([[id], "", generated_at], @now)
    end

    test "a remember date that is not a plain Devise timestamp is refused" do
      [[id], token, _generated_at] = remember_payload()
      refute Accounts.from_remember_cookie([[id], token, "1790424000"], @now)

      refute Accounts.from_remember_cookie(
               [[id], token, String.duplicate("9", 400) <> ".0"],
               @now
             )

      refute Accounts.from_remember_cookie(
               [[id], token, String.duplicate("9", 305) <> ".0"],
               @now
             )

      refute Accounts.from_remember_cookie([[id], token, 1_790_424_000.0], @now)
    end

    test "the store writes no rails_user_id into the Phoenix session cookie" do
      conn =
        conn(:get, "/")
        |> Map.put(:secret_key_base, String.duplicate("s", 64))
        |> put_req_cookie("_dawarich_session", @fixture["session_cookie"])
        |> Plug.Conn.fetch_cookies()

      opts =
        SessionStore.init(
          DawarichWeb.Endpoint.session_options()
          |> Keyword.delete(:store)
          |> Keyword.delete(:key)
        )

      cookie = SessionStore.put(conn, nil, %{"a" => 1, "rails_user_id" => 999}, opts)
      assert {_sid, %{"a" => 1} = stored} = Plug.Session.COOKIE.get(conn, cookie, opts)
      refute Map.has_key?(stored, "rails_user_id")
    end

    test "CSRF refuses missing secrets and malformed tokens but accepts the Rails legacy real token" do
      session = csrf_session()
      token = RailsCsrf.masked_token(session)
      refute RailsCsrf.valid?(%{}, token)
      refute RailsCsrf.valid?(%{"_csrf_token" => "not base64!"}, token)
      refute RailsCsrf.valid?(session, "not base64!")
      refute RailsCsrf.valid?(session, binary_part(token, 0, 43))
      refute RailsCsrf.valid?(session, nil)
      assert RailsCsrf.valid?(session, session["_csrf_token"])
    end

    test "the user's password hash never appears when the user is inspected" do
      user = current_user(session_cookie())
      refute inspect(user) =~ @salt
    end

    test "resolving the user logs no cookie, session value, salt or token" do
      level = Logger.level()
      Logger.configure(level: :debug)

      log =
        try do
          capture_log([level: :debug], fn ->
            assert RailsCsrf.valid?(csrf_session(), RailsCsrf.masked_token(csrf_session()))
            assert RailsCsrf.valid?(csrf_session(), @fixture["csrf"]["masked_token"])
            assert current_user(session_cookie() ++ remember_cookie())
            update_user(encrypted_password: "$2a$12$" <> String.duplicate("z", 53))
            refute current_user(session_cookie() ++ remember_cookie())
          end)
        after
          Logger.configure(level: level)
        end

      assert log =~ "users"

      secrets = [
        @fixture["session_cookie"],
        URI.decode_www_form(@fixture["session_cookie"]),
        @fixture["remember_cookie"],
        @salt,
        @user["encrypted_password"],
        @fixture["expected_session"]["session_id"],
        @fixture["rails_test_secret"],
        @fixture["csrf"]["masked_token"],
        csrf_session()["_csrf_token"]
      ]

      for secret <- secrets, do: refute(log =~ secret)
    end
  end
end
