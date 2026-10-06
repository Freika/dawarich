defmodule DawarichWeb.A12f3bN01Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Notifications}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{NotificationActions, RailsCsrf}

  defmodule Router do
    use Phoenix.Router

    pipeline :standalone_settings do
      plug DawarichWeb.HostAuthorization
      plug DawarichWeb.ForceSSL
      plug DawarichWeb.RateLimit
      plug DawarichWeb.RailsAuth
      plug DawarichWeb.Api.Body
      plug DawarichWeb.RailsHeaders
    end

    import DawarichWeb.NotificationFormRoutes
    import DawarichWeb.SettingsFormRoutes
    import DawarichWeb.SettingsMiscRoutes
    import DawarichWeb.OnboardingRoutes
    notification_form_routes()
    settings_form_routes()
    settings_misc_routes()
    onboarding_routes()
  end

  setup do
    actor = RailsUser.insert!(%{id: 73101, email: "n01@test"})
    other = RailsUser.insert!(%{id: 73102, email: "n01-other@test"})
    own = Notifications.create!(Repo, actor.id, :info, "Own", "Body")
    foreign = Notifications.create!(Repo, other.id, :info, "Foreign", "Body")
    %{actor: actor, other: other, own: own, foreign: foreign}
  end

  @tag a12f3b_case: "N01a"
  test "notifications legacy actions preserve owner scope and invalid row failure", ctx do
    conn = request(ctx.actor.id, :post, "/notifications/mark_as_read")
    assert apply(NotificationActions, :call, [conn, :mark_as_read]).status == 303
    assert Notifications.get(ctx.actor.id, ctx.own).read_at
    refute Notifications.get(ctx.other.id, ctx.foreign).read_at

    conn =
      request(ctx.actor.id, :delete, "/notifications/#{ctx.foreign}", %{"id" => "#{ctx.own}"})

    conn = %{conn | path_params: %{"id" => "#{ctx.foreign}"}}
    assert apply(NotificationActions, :call, [conn, :destroy]).status == 404
    session = RailsUser.session(ctx.actor.id)

    body =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(session),
        "id" => "#{ctx.own}"
      })

    routed =
      Plug.Test.conn(:delete, "/notifications/#{ctx.foreign}", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", "#{byte_size(body)}")
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
      |> Router.call([])

    assert routed.status == 404
    assert Notifications.get(ctx.actor.id, ctx.own)

    conn = request(ctx.actor.id, :post, "/notifications/destroy_all")
    assert apply(NotificationActions, :call, [conn, :destroy_all]).status == 303
    assert Notifications.get(ctx.actor.id, ctx.own) == nil
    assert Notifications.get(ctx.other.id, ctx.foreign)

    conn =
      request(ctx.actor.id, :post, "/notifications/destroy_all", %{
        "authenticity_token" => "invalid"
      })

    assert apply(NotificationActions, :call, [conn, :destroy_all]).status == 422
  end

  @tag a12f3b_case: "N01b"
  test "notification read validation failure preserves unread row", ctx do
    Repo.query!("UPDATE notifications SET title='', content='' WHERE id=$1", [ctx.own])
    notification = Notifications.get(ctx.actor.id, ctx.own)

    assert_raise Dawarich.Notifications.Invalid, fn ->
      Notifications.mark_read(ctx.actor.id, notification)
    end

    refute Notifications.get(ctx.actor.id, ctx.own).read_at
  end

  defp request(id, method, path, params \\ %{}) do
    session = RailsUser.session(id)

    Plug.Test.conn(method, path)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(
      :api_params,
      Map.merge(%{"authenticity_token" => RailsCsrf.masked_token(session)}, params)
    )
    |> assign(:api_query, %{})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(id))
  end
end
