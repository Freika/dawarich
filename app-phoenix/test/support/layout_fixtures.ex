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

  alias Dawarich.{Jobs, Repo}

  @now ~U[2026-09-26 12:00:00Z]

  def render(state) do
    user = insert(state)
    locale = DawarichWeb.Locale.resolve(state["locale"], user, %{})

    if url = state["manager_url"],
      do: System.put_env("MANAGER_URL", url),
      else: System.delete_env("MANAGER_URL")

    assigns = %{
      current_user: user,
      locale: locale,
      suggested_locale:
        DawarichWeb.Locale.suggest(state["accept_language"], nil, user, %{}, locale),
      self_hosted: state["self_hosted"],
      flash: %{},
      flash_messages: [],
      now: @now,
      request_path: URI.parse(state["path"]).path,
      query_params: %{},
      rails_csrf_token: nil,
      base_url: "http://www.example.com",
      page_title: page_title(locale, user),
      navbar: Dawarich.Navbar.load(user, now: @now, self_hosted: state["self_hosted"])
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

  defp insert(%{"user" => nil}), do: nil

  defp insert(%{"user" => user} = state) do
    insert_user(user)
    insert_family(state["family"], user["id"])

    Repo.insert_all(
      "notifications",
      for n <- state["notifications"] do
        at = naive(n["created_at"])

        %{
          id: n["id"],
          user_id: user["id"],
          title: n["title"],
          content: "x",
          kind: kind(n["kind"]),
          read_at: if(n["read"], do: at),
          created_at: at,
          updated_at: at
        }
      end
    )

    if state["supporter"] do
      hash =
        Base.encode16(:crypto.hash(:sha256, user["settings"]["supporter_email"]), case: :lower)

      Jobs.repo().query!(
        "INSERT INTO phoenix.supporter_checks (cache_key, result, checked_at) VALUES ($1, $2, $3)",
        ["dawarich/supporter:" <> hash, %{"supporter" => true}, @now]
      )
    end

    Dawarich.Accounts.get(user["id"])
  end

  defp insert_user(user) do
    stamp = ~N[2026-09-01 00:00:00]

    struct(Dawarich.Accounts.User,
      id: user["id"],
      email: user["email"],
      theme: user["theme"],
      settings: user["settings"],
      admin: user["admin"]
    )
    |> then(fn _ ->
      Repo.insert_all("users", [
        %{
          id: user["id"],
          email: user["email"],
          encrypted_password: "",
          theme: user["theme"] || "dark",
          settings: user["settings"] || %{},
          admin: user["admin"] || false,
          status: user["status"] || 1,
          plan: user["plan"] || 1,
          active_until: naive(user["active_until"]),
          subscription_source: user["subscription_source"] || 0,
          changelog_consent: user["changelog_consent"],
          created_at: stamp,
          updated_at: stamp
        }
      ])
    end)
  end

  defp insert_family(nil, _user_id), do: :ok

  defp insert_family(family, user_id) do
    stamp = ~N[2026-09-01 00:00:00]
    creator = family["creator"]
    if creator["id"] != user_id, do: insert_user(creator)

    Repo.insert_all("families", [
      %{
        id: family["id"],
        name: "F",
        creator_id: creator["id"],
        access_until: naive(family["access_until"]),
        created_at: stamp,
        updated_at: stamp
      }
    ])

    members = [
      {user_id, family["role"]} | if(creator["id"] != user_id, do: [{creator["id"], 0}], else: [])
    ]

    Repo.insert_all(
      "family_memberships",
      for(
        {id, role} <- members,
        do: %{
          family_id: family["id"],
          user_id: id,
          role: role,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )
  end

  defp naive(nil), do: nil
  defp naive(iso), do: NaiveDateTime.from_iso8601!(iso)

  defp kind("info"), do: 0
  defp kind("warning"), do: 1
  defp kind("error"), do: 2
  defp kind(kind) when kind in 0..2, do: kind
end
