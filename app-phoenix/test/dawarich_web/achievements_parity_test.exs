defmodule DawarichWeb.AchievementsParityTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Dawarich.Repo
  alias Dawarich.Test.{ParityHTML, RailsUser}

  @endpoint DawarichWeb.Endpoint
  @root "test/fixtures/achievements_ui"
  @stimulus "[data-controller], [data-action], [data-card-modal-target], [data-share-key], [data-achievement-card-target]"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    saved = {System.get_env("TIME_ZONE"), Application.fetch_env(:dawarich, :achievement_ui_now)}
    System.delete_env("TIME_ZONE")
    Application.put_env(:dawarich, :achievement_ui_now, fn -> ~U[2026-07-19 10:00:00Z] end)

    on_exit(fn ->
      {zone, clock} = saved
      if zone, do: System.put_env("TIME_ZONE", zone)

      case clock do
        {:ok, clock} -> Application.put_env(:dawarich, :achievement_ui_now, clock)
        :error -> Application.delete_env(:dawarich, :achievement_ui_now)
      end
    end)

    Repo.query!(
      "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES('DE','DEU','Germany',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now()),('FR','FRA','France',ST_GeomFromText('MULTIPOLYGON (((12.5 51.25,12.5 51.375,12.625 51.375,12.625 51.25,12.5 51.25)))',4326),now(),now())"
    )

    Repo.query!(
      "INSERT INTO regions(code,geom,created_at,updated_at) VALUES('DE-BY',ST_GeomFromText('MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))',4326),now(),now())"
    )

    :ok
  end

  for path <- Path.wildcard("test/fixtures/achievements_ui/*-*.json") do
    @fixture path |> File.read!() |> Jason.decode!()
    @external_resource path

    test "#{@fixture["name"]} matches the page Rails renders" do
      fixture = @fixture
      user_id = fixture["user_id"]

      RailsUser.insert!(%{
        id: user_id,
        email: "#{fixture["name"]}@example.invalid",
        settings: fixture["settings"]
      })

      if fixture["seed_state"],
        do:
          Repo.query!(
            "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
            [user_id, fixture["seed_state"]]
          )

      html = RailsUser.signed_in(user_id) |> get(fixture["path"]) |> html_response(200)
      rails = File.read!(Path.join(@root, fixture["name"] <> ".html"))
      phoenix = ParityHTML.fragment(html, ".ach-page")
      expected = ParityHTML.normalize(rails)

      assert phoenix == expected, ParityHTML.first_difference(phoenix, expected)
      assert stimulus(page(html)) == stimulus(rails)
    end
  end

  defp page(html),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(".ach-page") |> LazyHTML.to_html()

  defp stimulus(html),
    do:
      html
      |> ParityHTML.stimulus(@stimulus)
      |> Enum.map(fn {tag, attrs} ->
        {tag, Enum.map(attrs, fn {name, value} -> {name, undigest(value)} end)}
      end)

  defp undigest(value), do: String.replace(value, ~r/-[0-9a-f]{64}(?=\.webp\z)/, "")
end
