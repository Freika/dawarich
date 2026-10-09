defmodule DawarichWeb.AccountLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Repo
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.Translate

  @endpoint DawarichWeb.Endpoint
  @password "account-live-password-1"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    hash = Bcrypt.hash_pwd_salt(@password, log_rounds: 4)

    RailsUser.insert!(%{
      id: 9893,
      email: "account-live@dawarich.test",
      first_name: "Ada",
      api_key: "account-live-old-key",
      encrypted_password: hash,
      settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
    })

    Ownership.put!(Repo, "command:users.export_data", :oban)

    session =
      RailsUser.session(9893, %{"warden.user.user.key" => [[9893], binary_part(hash, 0, 29)]})

    %{session: session}
  end

  defp conn_for(session),
    do: build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))

  defp live_as(session),
    do: live(conn_for(session) |> RailsUser.connecting_as(9893), "/users/edit")

  defp api_key, do: Repo.query!("SELECT api_key FROM users WHERE id=9893").rows |> hd() |> hd()

  defp form_fields(html, selector) do
    for input <-
          html |> LazyHTML.from_document() |> LazyHTML.query(selector <> " input[type=hidden]"),
        into: %{} do
      {hd(LazyHTML.attribute(input, "name")), List.first(LazyHTML.attribute(input, "value"))}
    end
  end

  defp post_form(session, fields) do
    raw = URI.encode_query(fields)

    conn_for(session)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
    |> dispatch(@endpoint, :post, "/users", raw)
  end

  test "a new API key replaces the old one on the page after a confirmation", %{session: session} do
    {:ok, view, html} = live_as(session)
    assert html =~ "account-live-old-key"
    assert has_element?(view, "#rotate-api-key[data-confirm][phx-disable-with]")

    Dawarich.TtlCache.put({DawarichWeb.RateLimit, "account-live-old-key"}, %{plan: 1}, 60_000)
    assert api_status("account-live-old-key") == 200

    html = view |> element("#rotate-api-key") |> render_click()

    refute api_key() == "account-live-old-key"
    assert html =~ api_key()
    refute html =~ "account-live-old-key"
    assert api_status("account-live-old-key") == 401
    assert api_status(api_key()) == 200
  end

  defp api_status(key) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> key)
    |> get("/api/v1/points")
    |> Map.fetch!(:status)
  end

  test "a session from before a password change cannot rotate the key", %{session: session} do
    {:ok, view, _html} = live_as(session)

    Repo.query!("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      9893,
      Bcrypt.hash_pwd_salt("changed-elsewhere-1", log_rounds: 4)
    ])

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             view |> element("#rotate-api-key") |> render_click()

    assert api_key() == "account-live-old-key"
  end

  test "an export request queues one export and lands on the exports page with the notice", %{
    session: session
  } do
    {:ok, view, _html} = live_as(session)
    assert has_element?(view, "#export-data[data-confirm][phx-disable-with]")

    {:ok, exports} =
      view
      |> element("#export-data")
      |> render_click()
      |> follow_redirect(conn_for(session), "/exports")

    html = html_response(exports, 200)

    assert html =~
             Translate.t(
               "en",
               "controllers.settings.users.your_data_is_being_exported_you_will_receive_a_notification",
               %{}
             )

    assert Repo.query!(
             "SELECT count(*) FROM job_outbox WHERE command_type='users.export_data' AND aggregate_id=9893"
           ).rows == [[1]]
  end

  test "the profile form posts to the account handler and saves the change", %{session: session} do
    html = conn_for(session) |> get("/users/edit") |> html_response(200)
    fields = form_fields(html, "form#edit_user")

    saved =
      post_form(
        session,
        Map.merge(fields, %{
          "user[first_name]" => "Grace",
          "user[email]" => "account-live@dawarich.test",
          "user[current_password]" => @password
        })
      )

    assert saved.status == 303
    assert Repo.query!("SELECT first_name FROM users WHERE id=9893").rows == [["Grace"]]
  end

  test "a failed change returns to the page once with the errors and no password values", %{
    session: session
  } do
    html = conn_for(session) |> get("/users/edit") |> html_response(200)
    fields = form_fields(html, "form#edit_user")

    failed =
      post_form(
        session,
        Map.merge(fields, %{
          "user[email]" => "changed@dawarich.test",
          "user[current_password]" => "wrong-password-123"
        })
      )

    assert failed.status == 303
    assert get_resp_header(failed, "location") == ["http://www.example.com/users/edit"]
    session = RailsFormRequests.rails_session(failed)

    first = conn_for(session) |> RailsUser.connecting_as(9893) |> get("/users/edit")
    {:ok, view, page} = live(first)
    assert has_element?(view, "#error_explanation li")
    assert has_element?(view, "input#user_email[value='changed@dawarich.test']")
    refute page =~ "wrong-password-123"
    refute inspect(:sys.get_state(view.pid)) =~ "wrong-password-123"

    view |> element("#rotate-api-key") |> render_click()
    refute api_key() == "account-live-old-key"

    again =
      first
      |> RailsFormRequests.rails_session()
      |> conn_for()
      |> get("/users/edit")
      |> html_response(200)

    refute again =~ "error_explanation"
  end

  test "the delete form posts to the deletion handler with a token it accepts", %{
    session: session
  } do
    html = conn_for(session) |> get("/users/edit") |> html_response(200)
    fields = form_fields(html, "#delete_account_modal form")
    assert fields["_method"] == "delete"

    deleted = post_form(session, Map.put(fields, "password", @password))

    assert deleted.status == 302
    assert get_resp_header(deleted, "location") == ["http://www.example.com/"]

    assert Repo.query!(
             "SELECT count(*) FROM job_outbox WHERE aggregate_id=9893 AND command_type='users.destroy'"
           ).rows == [[1]]
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "account-budget-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:dawarich, :repo, :query], &__MODULE__.handle_query/4, self())
    result = fun.()
    :telemetry.detach(id)
    {result, drain(0)}
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end

  test "the page stays within the Rails-era query budget", %{session: session} do
    {conn, static} =
      queries(fn -> get(conn_for(session) |> RailsUser.connecting_as(9893), "/users/edit") end)

    {_, connected} = queries(fn -> {:ok, _view, _html} = live(conn) end)

    assert static <= 4
    assert connected <= 4
  end
end
