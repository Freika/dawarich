defmodule DawarichWeb.NotificationsParityTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Dawarich.Test.{NativeNotificationCorpus, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/notifications"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
  end

  for file <- Path.wildcard("test/fixtures/notifications/*.json") do
    @name Path.basename(file, ".json")

    test "#{@name} preserves recorded notification business content and read links" do
      state = @dir |> Path.join(@name <> ".json") |> File.read!() |> Jason.decode!()
      %{"id" => id, "email" => email, "settings" => settings} = state["user"]
      RailsUser.insert!(%{id: id, email: email, settings: settings})
      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all(
        "notifications",
        for n <- state["notifications"] do
          %{
            id: n["id"],
            user_id: id,
            title: n["title"],
            content: n["content"],
            kind: n["kind"],
            read_at: if(n["read"], do: now),
            created_at: NaiveDateTime.add(now, -n["offset"]),
            updated_at: now
          }
        end
      )

      html = get(RailsUser.signed_in(id), state["path"]) |> html_response(200)
      rails = File.read!(Path.join(@dir, @name <> ".html"))

      NativeNotificationCorpus.assert_page(html, rails)

      assert html =~ ">#{state["title"]}</title>"
    end
  end
end
