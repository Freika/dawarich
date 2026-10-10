defmodule Dawarich.Imports.Trek.DayNotes do
  @moduledoc false
  alias Dawarich.Imports.Trek.{Itinerary, Payload}
  alias Dawarich.Ingest.Ruby

  def text_for(day) do
    lines = [String.trim(Ruby.to_s(day["notes"]))]

    lines =
      lines ++
        Enum.map(day["day_notes"] || [], fn note ->
          Enum.reject(
            [
              if(Ruby.present?(note["time"]), do: Ruby.to_s(note["time"])),
              String.trim(Ruby.to_s(note["text"]))
            ],
            &is_nil/1
          )
          |> Enum.join(" ")
        end)

    text =
      lines
      |> Enum.reject(&Ruby.blank?/1)
      |> Enum.join("\n")
      |> String.to_charlist()
      |> Enum.take(10_000)
      |> List.to_string()

    if Ruby.present?(text), do: text
  end

  def sync!(ctx, trip, before, after_snapshot) do
    before = texts(before)
    after_texts = texts(after_snapshot)

    for date <- Enum.uniq(Map.keys(before) ++ Map.keys(after_texts)),
        before[date] != after_texts[date] do
      notes =
        ctx.repo.query!(
          "SELECT id,body,source_digest FROM notes WHERE attachable_type='Trip' AND attachable_id=$1 AND noted_at::date=$2 ORDER BY id LIMIT 1 FOR UPDATE",
          [trip, date],
          log: false
        ).rows

      text = after_texts[date]

      case notes do
        [] ->
          if text,
            do:
              Itinerary.insert!(ctx, "notes", %{
                user_id: ctx.user_id,
                attachable_type: "Trip",
                attachable_id: trip,
                body: text,
                noted_at: NaiveDateTime.new!(date, ~T[12:00:00]),
                source_digest: digest(text)
              })

        [[id, body, source_digest]] ->
          if source_digest not in [nil, ""] and source_digest == digest(body) do
            if text do
              ctx.repo.query!(
                "UPDATE notes SET body=$2,source_digest=$3,updated_at=$4 WHERE id=$1",
                [id, text, digest(text), DateTime.to_naive(ctx.now)],
                log: false
              )
            else
              ctx.repo.query!("DELETE FROM notes WHERE id=$1", [id], log: false)
            end
          end
      end
    end

    :ok
  end

  defp texts(snapshot) do
    for day <- (snapshot || %{})["days"] || [],
        text = text_for(day),
        text != nil,
        into: %{},
        do: {Payload.date!(day["date"], "day date"), text}
  end

  defp digest(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
