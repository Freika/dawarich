defmodule DawarichWeb.A12f3bN02Test do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.{Notifications, Cable.Bus, Cable.TurboEvents}
  alias Dawarich.Test.{A12a, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    actor =
      RailsUser.insert!(%{
        id: 73201,
        email: "n02@test",
        settings: %{"onboarding_completed" => true, "locale" => "de"}
      })

    A12a.start_bus!()
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag a12f3b_case: "N02a"
  test "native notification publication updates the authorized connected navbar", ctx do
    id = Notifications.create!(Repo, ctx.actor.id, :info, "Created", "Body")
    {:ok, view, _} = live_as(ctx)
    stream = Dawarich.RailsMessages.broadcasting([{:user, ctx.actor.id}, "notifications"])
    {:ok, _} = Bus.subscribe(stream)
    assert_receive {:redix_pubsub, _, _, :subscribed, _}

    assert apply(Notifications, :update_with_broadcast!, [
             Repo,
             ctx.actor.id,
             id,
             %{"title" => "Updated", "content" => "New body"}
           ]) == :ok

    assert TurboEvents.notifications(Repo, Repo) == 2
    for _ <- 1..4, do: assert_receive({:redix_pubsub, _, _, :message, _})
    :sys.get_state(Bus)
    html = render(view)
    assert html =~ "Updated"
    refute html =~ ">Created<"
    assert html =~ "notifications-badge"
    assert Notifications.get(ctx.actor.id, id).title == "Updated"
  end

  @tag a12f3b_case: "N02b"
  test "notification actions fail after signout in another tab", ctx do
    id = Notifications.create!(Repo, ctx.actor.id, :info, "Keep", "Body")
    {:ok, view, _} = live_as(ctx)

    body =
      URI.encode_query(%{"authenticity_token" => DawarichWeb.RailsCsrf.masked_token(ctx.session)})

    logout =
      Plug.Test.conn(:delete, "/users/sign_out", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", "#{byte_size(body)}")
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(ctx.session))
      |> DawarichWeb.AuthHandler.call(enabled: true, registration_enabled: true)

    assert logout.status == 303
    render_click(view, "destroy_all")
    assert_redirect(view, "/users/sign_in")
    assert Notifications.get(ctx.actor.id, id)
  end

  defp live_as(ctx) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> RailsUser.connecting_as(ctx.actor.id)
    |> live("/notifications")
  end
end
