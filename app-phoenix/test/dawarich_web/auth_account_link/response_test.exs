defmodule DawarichWeb.AuthAccountLink.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, SessionCookie}
  alias Dawarich.{RailsCookies, Repo}
  alias Dawarich.Test.NativeAuthHTTP
  alias DawarichWeb.AuthAccountLink.Response
  @secret "a11e-response-synthetic-cookie-secret"
  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()
  @now DateTime.from_unix!(@source["at"])

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("APPLICATION_PROTOCOL", "http")
    System.put_env("RAILS_ENV", "test")

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  test "owned account-link responses preserve no-store form state and source 302 notices" do
    assert Code.ensure_loaded?(Response)
    context = %{secret: @secret, clock: fn -> @now end}

    for locale <- ~w(en de es fr pl ca zh) do
      row = @source["challenge_#{locale}"]

      {session, _} =
        SessionCookie.for_form(Map.drop(row["session"], ~w(session_id _csrf_token)), @secret)

      user = %{
        id: row["before"]["id"],
        email: row["before"]["email"],
        encrypted_password: row["before"]["encrypted_password"]
      }

      pending = %{session: session, user: user, pending: session["pending_oauth_link"]}
      result = Response.form(request(session), pending, context)
      assert result.status == 200 and result.halted
      headers(result, row)
      assert decoded(result) == session
      expected = File.read!("test/fixtures/auth/account_link/challenge_#{locale}.html")
      assert NativeAuthHTTP.fields(result.resp_body) == NativeAuthHTTP.fields(expected)

      for selector <- ["h2", "label", "p", "a"],
          do:
            assert(
              NativeAuthHTTP.text(result.resp_body, ".card-body " <> selector) ==
                NativeAuthHTTP.text(expected, ".card-body " <> selector)
            )

      assert NativeAuthHTTP.text(result.resp_body, "title") ==
               NativeAuthHTTP.text(expected, "title")

      for name <- ~w(description viewport referrer theme-color) do
        dom = LazyHTML.query(LazyHTML.from_document(result.resp_body), "meta[name='#{name}']")
        source = LazyHTML.query(LazyHTML.from_document(expected), "meta[name='#{name}']")
        assert LazyHTML.attribute(dom, "content") == LazyHTML.attribute(source, "content"), name
      end

      assert result.resp_body =~ "/native/auth_http.js"

      for {path, node} <- [{"/auth/account_link/challenge", 0}, {"/auth/account_link/email", 1}] do
        tokens =
          result.resp_body
          |> LazyHTML.from_document()
          |> LazyHTML.query("form input[name=authenticity_token]")
          |> LazyHTML.attribute("value")

        assert ActionCsrf.valid?(session, Enum.at(tokens, node), "POST", path)
        refute ActionCsrf.valid?(session, Enum.at(tokens, node), "POST", "/users/sign_in")
      end

      for {kind, source} <- [
            {:sign_in, @source["success_#{locale}"]},
            {:link_only, @source["otp"]}
          ] do
        completed = Response.completed(request(session), Map.put(pending, :kind, kind), context)
        assert completed.status == 302 and completed.halted
        headers(completed, source)
        assert URI.parse(hd(get_resp_header(completed, "location"))).path == source["location"]
        state = decoded(completed)

        notice_key =
          if kind == :sign_in,
            do: "pending_is_now_linked_to_your_account",
            else: "linked_sign_in_with_two_factor"

        binding = if kind == :sign_in, do: "pending", else: "provider"

        {:ok, notice} =
          Dawarich.I18n.t(locale, "controllers.auth.account_links." <> notice_key, %{
            binding => "OpenID Connect"
          })

        assert state["flash"] == %{"discard" => [], "flashes" => %{"notice" => notice}}
        assert state["user_return_to"] == "/trips"
        assert state["_csrf_token"] == session["_csrf_token"]
        assert Map.has_key?(state, "warden.user.user.key") == (kind == :sign_in)
        refute Map.has_key?(completed.resp_cookies, "remember_user_token")

        next =
          request(state)
          |> fetch_query_params()
          |> DawarichWeb.Locale.call([])
          |> DawarichWeb.LayoutAssigns.call([])

        assert next.assigns.flash_messages == [{"notice", notice}]
        refute Map.has_key?(next.assigns.rails_session, "flash")
      end

      assert_raise DawarichWeb.RailsSession.Overflow, fn ->
        Response.completed(
          request(session),
          %{pending | session: Map.put(session, "oversize", String.duplicate("x", 5000))}
          |> Map.put(:kind, :sign_in),
          context
        )
      end
    end
  end

  test "owned challenge preserves escaped incoming alert once in native shell" do
    for locale <- ~w(en de es fr pl ca zh) do
      row = @source["challenge_alert_#{locale}"]

      {session, _} =
        SessionCookie.for_form(
          row["session"]
          |> Map.drop(~w(session_id _csrf_token))
          |> Map.put("flash", row["incoming_flash"]),
          @secret
        )

      pending = %{
        session: session,
        user: %{email: row["before"]["email"]},
        pending: session["pending_oauth_link"]
      }

      conn = Response.form(request(session), pending, %{secret: @secret})

      card =
        conn.resp_body
        |> LazyHTML.from_document()
        |> LazyHTML.query("#flash-messages .alert-error")

      assert card |> LazyHTML.query("span") |> LazyHTML.text() |> String.trim() ==
               "A11e <script>synthetic</script> & retry"

      assert LazyHTML.query(card, "script") |> LazyHTML.to_tree() == []
      refute Map.has_key?(decoded(conn), "flash")

      next =
        Response.form(request(decoded(conn)), %{pending | session: decoded(conn)}, %{
          secret: @secret
        })

      assert next.resp_body
             |> LazyHTML.from_document()
             |> LazyHTML.query("#flash-messages .alert-error")
             |> LazyHTML.to_tree() == []
    end
  end

  test "source blank incoming link alerts retain exact shell content and expire once" do
    for locale <- ~w(en de es fr pl ca zh), alert <- ["", "  ", nil, false] do
      row = @source["challenge_alert_#{locale}"]

      {session, _} =
        SessionCookie.for_form(
          row["session"]
          |> Map.drop(~w(session_id _csrf_token))
          |> Map.put("flash", row["incoming_flash"]),
          @secret
        )

      session = put_in(session, ["flash", "flashes", "alert"], alert)

      pending = %{
        session: session,
        user: %{email: row["before"]["email"]},
        pending: session["pending_oauth_link"]
      }

      conn = Response.form(request(session), pending, %{secret: @secret})
      dom = LazyHTML.from_document(conn.resp_body)
      alerts = LazyHTML.query(dom, "#flash-messages .alert-error")
      assert Enum.count(alerts) == 1

      assert alerts |> LazyHTML.query("span") |> LazyHTML.text() ==
               if(is_nil(alert), do: "", else: to_string(alert))

      assert Enum.empty?(LazyHTML.query(dom, ".card-body .alert-error"))
      refute Map.has_key?(decoded(conn), "flash")

      next =
        Response.form(request(decoded(conn)), %{pending | session: decoded(conn)}, %{
          secret: @secret
        })

      assert Enum.empty?(
               LazyHTML.query(
                 LazyHTML.from_document(next.resp_body),
                 "#flash-messages .alert-error"
               )
             )
    end
  end

  defp request(session) do
    Phoenix.ConnTest.build_conn(:get, "/auth/account_link/challenge")
    |> assign(:rails_session, session)
    |> assign(:current_user, nil)
    |> assign(:rails_locked, nil)
    |> assign(:now, @now)
  end

  defp decoded(conn) do
    {:ok, session} =
      RailsCookies.decrypt(
        conn.resp_cookies["_dawarich_session"].value,
        "_dawarich_session",
        @secret,
        @now
      )

    session
  end

  defp headers(conn, source) do
    for {key, expected} <- source["headers"],
        do: assert(get_resp_header(conn, key) == [expected], key)

    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-account-link"]

    assert get_resp_header(
             DawarichWeb.RailsHeaders.call(%{conn | state: :set}, []),
             "cache-control"
           ) == ["no-store"]

    cookie = conn.resp_cookies["_dawarich_session"]
    assert cookie.http_only and cookie.same_site == "Lax" and cookie.path == "/"
    assert cookie.secure == false
  end
end
