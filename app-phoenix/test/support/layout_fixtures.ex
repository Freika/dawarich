defmodule Dawarich.Test.LayoutFixtures do
  @moduledoc false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  @dir "test/fixtures/layout"

  def names do
    @dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.reject(&(&1 == "flash_messages"))
  end

  def load(name) do
    {
      File.read!(Path.join(@dir, name <> ".html")),
      @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
    }
  end

  def load_head(name), do: File.read!(Path.join(@dir, name <> ".head.html"))

  def flash_messages,
    do: @dir |> Path.join("flash_messages.json") |> File.read!() |> Jason.decode!()

  def render(state) do
    user = insert_user(state["user"])
    locale = DawarichWeb.Locale.resolve(nil, user, %{})

    assigns = %{
      current_user: user,
      locale: locale,
      suggested_locale:
        DawarichWeb.Locale.suggest(state["accept_language"], nil, user, %{}, locale),
      self_hosted: state["self_hosted"],
      flash: %{},
      flash_messages: [],
      now: ~U[2026-09-26 12:00:00Z],
      request_path: if(user, do: "/notifications", else: "/users/sign_in"),
      query_params: %{},
      rails_csrf_token: nil,
      page_title: page_title(locale, user),
      navbar: []
    }

    inner = render_component(&DawarichWeb.Layouts.app/1, Map.put(assigns, :inner_content, ""))

    render_component(
      &DawarichWeb.Layouts.root/1,
      Map.put(assigns, :inner_content, Phoenix.HTML.raw(inner))
    )
  end

  defp page_title(_locale, nil), do: nil
  defp page_title("de", _user), do: "Benachrichtigungen"
  defp page_title(_locale, _user), do: "Notifications"

  defp insert_user(nil), do: nil

  defp insert_user(state) do
    struct(Dawarich.Accounts.User,
      id: state["id"],
      email: state["email"],
      theme: state["theme"],
      settings: state["settings"],
      admin: state["admin"]
    )
  end
end
