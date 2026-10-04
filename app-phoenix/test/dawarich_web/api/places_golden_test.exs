defmodule DawarichWeb.Api.PlacesGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Accounts
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Test.ApiGolden
  alias Dawarich.PlacesApi

  @golden "test/fixtures/api_places/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users tags places taggings visits place_visits notes)
  @written ~w(tags places taggings visits place_visits notes)
  @now @golden["now"] |> DateTime.from_iso8601() |> elem(1)

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)
      seed(@kase)
      before = rows(@tables)
      ApiGolden.check(@kase, port, puma)

      if @kase["after"], do: domain!(@kase), else: assert(rows(@tables) == before)
    end
  end

  test "a failure after the first write rolls every table back and hands the request to Rails" do
    kase = Enum.find(@golden["cases"], &(&1["name"] == "destroy_linked"))
    seed(kase)

    Repo.query!(
      "CREATE FUNCTION pg_temp.refuse() RETURNS trigger LANGUAGE plpgsql AS " <>
        "$$BEGIN RAISE EXCEPTION 'refused'; END$$"
    )

    Repo.query!(
      "CREATE TRIGGER refuse_notes BEFORE DELETE ON notes FOR EACH ROW EXECUTE FUNCTION pg_temp.refuse()"
    )

    before = rows(@tables)
    {action, user, params} = prepare(kase)

    assert {:replay, _reason} = PlacesApi.run(action, user, params, @now)
    assert rows(@tables) == before
  end

  test "tags whose taggings share a created_at come in tagging id order" do
    seed(Enum.find(@golden["cases"], &(&1["name"] == "show_active_visits")))

    for {id, tag} <- [{950_699, 950_101}, {950_698, 950_102}] do
      Repo.query!(
        "INSERT INTO taggings (id, taggable_type, taggable_id, tag_id, created_at, updated_at) " <>
          "VALUES ($1, 'Place', 950202, $2, $3, $3)",
        [id, tag, ~N[2026-09-01 09:00:00]]
      )
    end

    user = Accounts.by_api_key("phoenix-a4pl-golden-key")

    assert {:ok, 200, {:object, pairs}, []} =
             PlacesApi.run(:show, user, %{"id" => "950202"}, @now)

    {"tags", tags} = List.keyfind(pairs, "tags", 0)
    assert for({:object, [{"id", id} | _]} <- tags, do: id) == [950_102, 950_101]
    assert List.keyfind(pairs, "icon", 0) == {"icon", nil}
  end

  defp seed(kase) do
    Dawarich.FixtureCleanup.delete!(Repo, ~w(places))

    for [table, rows] <- @golden["setups"][kase["setup"]], row <- rows do
      true = table in @tables
      ApiGolden.insert!(table, row)
    end

    for {name, value} <- @golden["sequences"],
        do: Repo.query!("SELECT setval($1::text::regclass, $2, false)", [name, value])
  end

  defp domain!(kase) do
    for table <- Enum.reverse(@tables), do: Repo.query!("DELETE FROM #{table}")
    seed(kase)
    {action, user, params} = prepare(kase)

    got =
      case PlacesApi.run(action, user, params, @now) do
        {:ok, status, term, _headers} -> {status, term |> Ruby.json() |> IO.iodata_to_binary()}
        :no_content -> {204, ""}
      end

    assert got == {kase["response"]["status"], kase["response"]["body"]}
    assert rows(@written) == kase["after"]
  end

  defp prepare(kase) do
    %{"method" => method, "target" => target, "headers" => headers, "body" => body} =
      kase["request"]

    [key] = for ["Authorization", "Bearer " <> key] <- headers, do: key
    params = if body == "", do: %{}, else: Jason.decode!(body)

    case String.split(URI.parse(target).path, "/") do
      ["", "api", "v1", "places"] ->
        {:create, Accounts.by_api_key(key), params}

      ["", "api", "v1", "places", id] ->
        {action(method), Accounts.by_api_key(key), Map.put(params, "id", id)}
    end
  end

  defp action("DELETE"), do: :destroy
  defp action(method) when method in ~w(PATCH PUT), do: :update

  defp rows(tables) do
    Repo.query!("SELECT set_config('TimeZone', 'UTC', true)")

    Map.new(tables, fn table ->
      values =
        Repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows
        |> Enum.map(fn [json] -> json |> Jason.decode!() |> Map.reject(&is_nil(elem(&1, 1))) end)

      {table, values}
    end)
  end
end
