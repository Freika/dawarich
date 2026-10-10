defmodule DawarichWeb.NotificationsParityTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Dawarich.Test.{ParityHTML, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @dir "test/fixtures/notifications"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  for file <- Path.wildcard("test/fixtures/notifications/*.json") do
    @name Path.basename(file, ".json")

    test "#{@name} matches the page Rails renders" do
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

      assert ParityHTML.fragment(html, "div.px-4.flex-1 > div.flex > *") ==
               ParityHTML.normalize(rails)

      assert html =~ ">#{state["title"]}</title>"
    end
  end
end
