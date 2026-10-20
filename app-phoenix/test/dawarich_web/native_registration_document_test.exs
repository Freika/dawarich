defmodule DawarichWeb.NativeRegistrationDocumentTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint

  setup do
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    env = %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"}
    old = Map.new(env, fn {k, _} -> {k, System.get_env(k)} end)
    System.put_env(env)

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    Dawarich.State.put_registration_enabled(Repo, true)
    %{guest: %{"_csrf_token" => RailsCsrf.new_token()}}
  end

  test "native signup preserves invitation field policy and empty rejected credentials" do
    invitation = %{
      token: "synthetic-invitation",
      email: "invite@example.test",
      name: "Synthetic family",
      inviter: "inviter@example.invalid"
    }

    html =
      DawarichWeb.AuthRegistration.Form.render(
        "synthetic-csrf",
        invitation.email,
        ["Validation error"],
        invitation,
        "de"
      )
      |> IO.iodata_to_binary()

    dom = LazyHTML.from_fragment(html)
    assert Enum.count(LazyHTML.query(dom, "form[data-auth-form]")) == 1

    assert LazyHTML.attribute(
             LazyHTML.query(dom, "input[name='user[invitation_token]']"),
             "value"
           ) == [invitation.token]

    assert Enum.count(LazyHTML.query(dom, "input[name='user[email]'][readonly]")) == 1
    assert Enum.count(LazyHTML.query(dom, "input[type=password]")) == 2
    assert Enum.count(LazyHTML.query(dom, "input[name='user[password_confirmation]']")) == 1

    for node <- LazyHTML.query(dom, "input[type=password]"),
        do: assert(LazyHTML.attribute(node, "value") in [[], [""]])

    assert Enum.count(LazyHTML.query(dom, "[data-auth-error-summary][tabindex='-1']")) == 1
  end

  test "signup validation creates no user or intent", c do
    before = Repo.query!("SELECT count(*) FROM users", [], log: false).rows
    intents = Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows

    params = %{
      "authenticity_token" => RailsCsrf.masked_form_token(c.guest, "/users", "POST"),
      "user[email]" => "invalid-signup@example.test",
      "user[password]" => "short",
      "user[password_confirmation]" => "different"
    }

    response = RailsFormRequests.post_form(c.guest, URI.encode_query(params), [], "/users")
    assert response.status == 422
    assert response.resp_body =~ "/native/auth_http.js"
    assert Repo.query!("SELECT count(*) FROM users", [], log: false).rows == before
    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == intents
    state = RailsFormRequests.rails_session(response)
    refute Map.has_key?(state, "warden.user.user.key")

    for node <- LazyHTML.query(LazyHTML.from_document(response.resp_body), "input[type=password]"),
        do: assert(LazyHTML.attribute(node, "value") in [[], [""]])

    Dawarich.State.put_registration_enabled(Repo, false)
    denied = RailsFormRequests.post_form(c.guest, URI.encode_query(params), [], "/users")
    assert denied.status == 302
    assert Repo.query!("SELECT count(*) FROM users", [], log: false).rows == before
  end

  test "signed-in users update or delete through account classification never registration", c do
    page =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.guest))
      |> get("/users/sign_up")

    assert page.resp_body =~ "/native/auth_http.js"

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "classification@example.test",
        api_key: "synthetic",
        settings: %{}
      })

    session = RailsUser.session(actor.id)

    for method <- ["put", "patch", "delete"] do
      fields = %{
        "_method" => method,
        "authenticity_token" =>
          RailsCsrf.masked_form_token(session, "/users", String.upcase(method))
      }

      response = RailsFormRequests.post_form(session, URI.encode_query(fields), [], "/users")
      refute get_resp_header(response, "x-dawarich-auth-owner") == ["native-registration"]
      assert response.status == if(method == "delete", do: 302, else: 303)
      assert Repo.get!(Dawarich.Auth.Account, actor.id).email == actor.email
    end
  end
end
