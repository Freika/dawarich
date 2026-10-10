defmodule DawarichWeb.AuthAccountLink.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, SessionCookie}
  alias Dawarich.{RailsCookies, Repo, Test.ParityHTML}
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
      actual_body = ParityHTML.fragment(result.resp_body, "body")
      expected_body = ParityHTML.fragment(expected, "body")
      assert actual_body == expected_body, ParityHTML.first_difference(actual_body, expected_body)
      runtime = ["script", "link[rel=modulepreload]", "meta[name=phoenix-csrf-token]"]
      actual_head = ParityHTML.without(result.resp_body, runtime, "head")
      expected_head = ParityHTML.without(expected, runtime, "head")
      assert actual_head == expected_head, ParityHTML.first_difference(actual_head, expected_head)

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

  test "owned challenge matches Rails incoming alert escaping presence and one-request lifetime" do
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
      expected = File.read!("test/fixtures/auth/account_link/challenge_alert_#{locale}.html")
      actual = ParityHTML.fragment(conn.resp_body, "body")
      expected_body = ParityHTML.fragment(expected, "body")
      assert actual == expected_body, ParityHTML.first_difference(actual, expected_body)

      card =
        conn.resp_body |> LazyHTML.from_document() |> LazyHTML.query(".card-body .alert-error")

      assert card |> LazyHTML.text() |> String.trim() == "A11e <script>synthetic</script> & retry"
      assert LazyHTML.query(card, "script") |> LazyHTML.to_tree() == []
      refute Map.has_key?(decoded(conn), "flash")

      next =
        Response.form(request(decoded(conn)), %{pending | session: decoded(conn)}, %{
          secret: @secret
        })

      assert next.resp_body
             |> LazyHTML.from_document()
             |> LazyHTML.query(".card-body .alert-error")
             |> LazyHTML.to_tree() == []

      for alert <- ["", "  ", nil, false] do
        blank = put_in(session, ["flash", "flashes", "alert"], alert)
        conn = Response.form(request(blank), %{pending | session: blank}, %{secret: @secret})

        assert conn.resp_body
               |> LazyHTML.from_document()
               |> LazyHTML.query(".card-body .alert-error")
               |> LazyHTML.to_tree() == []
      end
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
