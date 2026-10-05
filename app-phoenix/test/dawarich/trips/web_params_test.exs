defmodule Dawarich.Trips.WebParamsTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Trips.{WebDescription, WebParams}

  @root "test/fixtures/trips/remaining/"
  @effects @root
           |> Kernel.<>("effects.json")
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses @root
             |> Kernel.<>("responses.json")
             |> File.read!()
             |> Jason.decode!()
             |> Map.fetch!("responses")
  @fields ~w(name started_at ended_at description)

  defp previous(entry) do
    case entry["before"]["trips"] do
      [] ->
        %{}

      [trip] ->
        %{
          name: trip["name"],
          started_at: naive(trip["started_at"]),
          ended_at: naive(trip["ended_at"]),
          description:
            case entry["before"]["action_text_rich_texts"] do
              [] -> nil
              [row] -> row["body"]
            end
        }
    end
  end

  defp naive(nil), do: nil
  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  test "trip attributes match Rails casts and description storage" do
    for entry <- @effects,
        entry["request"]["owner"] == "oban",
        entry["request"]["fault"] == nil,
        entry["request"]["method"] in ~w(POST PATCH),
        Map.has_key?(entry["request"]["params"], "trip") do
      attrs = Map.take(entry["request"]["params"]["trip"], @fields)
      response = Enum.find(@responses, &(&1["name"] == entry["name"]))
      user = %{settings: entry["before"]["actor"]["settings"]}
      result = WebParams.parse(user, attrs, previous(entry), %{repo: Repo, locale: "en"})

      cond do
        String.contains?(entry["name"], "embedded") ->
          assert {:replay, _} = result

        response["error"] != nil ->
          assert {:invalid, _, _} = result

        response["status"] == 422 ->
          assert {:invalid, errors, entered} = result
          assert Enum.map(errors, &elem(&1, 1)) == Enum.drop(response["errors"], 1), entry["name"]
          assert entered.raw == attrs

          for control <- response["controls"],
              control["attributes"]["name"] in ~w(trip[name] trip[started_at] trip[ended_at]) do
            attributes = control["attributes"]

            key =
              attributes["name"]
              |> String.replace_prefix("trip[", "")
              |> String.trim_trailing("]")

            assert entered.values[key] == attributes["value"], entry["name"] <> " " <> key
          end

        true ->
          assert {:ok, changes} = result
          [trip] = entry["after"]["trips"]
          assert changes.name == trip["name"], entry["name"]

          assert NaiveDateTime.compare(changes.started_at, naive(trip["started_at"])) == :eq,
                 entry["name"]

          assert NaiveDateTime.compare(changes.ended_at, naive(trip["ended_at"])) == :eq,
                 entry["name"]

          if Map.has_key?(attrs, "description") do
            [rich] = entry["after"]["action_text_rich_texts"]
            assert changes.description == rich["body"], entry["name"]
          else
            assert changes.description == :unchanged
          end
      end
    end

    user = %{settings: %{"timezone" => "UTC"}}

    valid = %{
      "name" => "Auwald",
      "started_at" => "2026-10-03T09:00:00Z",
      "ended_at" => "2026-10-03T12:00:00+02:00"
    }

    assert {:ok, changes} = WebParams.parse(user, valid, %{}, %{repo: Repo, locale: "en"})
    assert NaiveDateTime.compare(changes.started_at, ~N[2026-10-03 09:00:00]) == :eq
    assert NaiveDateTime.compare(changes.ended_at, ~N[2026-10-03 10:00:00]) == :eq

    assert {:ok, fractional} =
             WebParams.parse(
               %{settings: %{"timezone" => "Europe/Berlin"}},
               Map.put(valid, "started_at", "2026-10-03T09:00:00.987654"),
               %{},
               %{repo: Repo}
             )

    assert fractional.started_at == ~N[2026-10-03 07:00:00.987654]

    for value <- [
          "October 3 2026",
          "2026-10-03",
          "2026-10-03T09:00CET",
          %{},
          ["2026-10-03T09:00"]
        ] do
      assert {:replay, _} =
               WebParams.parse(user, Map.put(valid, "started_at", value), %{}, %{repo: Repo})
    end

    for settings <- ["legacy", %{"timezone" => "Unknown/Zone"}, %{"timezone" => []}] do
      assert {:replay, _} = WebParams.parse(%{settings: settings}, valid, %{}, %{repo: Repo})
    end

    assert {:ok, :unchanged} = WebDescription.prepare(:omitted, nil)
    assert {:ok, ""} = WebDescription.prepare("", "<div>Before</div>")

    for entry <-
          "test/fixtures/trips/descriptions.json"
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("cases") do
      if entry["expect"] == "phoenix" do
        assert {:ok, body} = WebDescription.prepare(entry["body"], nil)

        expected =
          cond do
            is_nil(entry["body"]) ->
              nil

            is_nil(entry["rendered"]) ->
              ""

            true ->
              entry["rendered"]
              |> String.replace_prefix("<div class=\"trix-content\">\n  ", "")
              |> String.replace_suffix("\n\n</div>\n", "")
          end

        assert body == expected, entry["name"]
      else
        assert {:replay, _} = WebDescription.prepare(entry["body"], nil)
      end
    end

    assert {:replay, _} =
             WebDescription.prepare(
               "<div>After</div>",
               "<action-text-attachment></action-text-attachment>"
             )
  end
end
