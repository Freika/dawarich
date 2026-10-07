defmodule Dawarich.Achievements.OgImage do
  @moduledoc false
  alias Dawarich.Achievements.{PublicCard, UiText}
  alias Dawarich.{Storage, TtlCache}
  require EEx
  EEx.function_from_file(:defp, :template, Path.join(__DIR__, "og_image.svg.eex"), [:assigns])

  @accents %{
    "common" => "#aeb8c5",
    "rare" => "#58b6ff",
    "epic" => "#bb85ef",
    "legendary" => "#ffc266"
  }

  def call(repo, uuid, opts \\ []) do
    case repo.query!(
           "SELECT p.id,p.user_id,p.achievement_key,u.settings,COALESCE(e.state,'{}'::jsonb) FROM achievement_progresses p JOIN users u ON u.id=p.user_id AND u.deleted_at IS NULL LEFT JOIN achievement_progresses e ON e.user_id=p.user_id AND e.achievement_key='exploration' WHERE p.sharing_uuid=$1 AND p.sharing_enabled=true",
           [uuid],
           log: false
         ).rows do
      [[id, owner, key, settings, state]] ->
        case PublicCard.load(repo, uuid, %{}) do
          {:ok, view} ->
            cache_key = cache_key(id, owner, key, settings, state, view.locale)

            png =
              TtlCache.fetch(cache_key, :timer.hours(1), fn ->
                Keyword.get(opts, :render, &render/1).(view)
              end)

            {:ok, png}

          :not_found ->
            :not_found

          :handoff ->
            {:error, :unsupported_state}
        end

      [] ->
        :not_found
    end
  end

  defp cache_key(id, owner, key, settings, state, locale) do
    zone = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")
    digest = :crypto.hash(:sha256, Jason.encode!(state))
    {__MODULE__, id, owner, key, locale, zone, digest}
  end

  def svg(view) do
    rarity = String.downcase(view.card["rarity"] || "common")
    accent = if view.locked, do: "#68717d", else: Map.get(@accents, rarity, @accents["common"])
    label = view.card["earned_label"]

    status =
      cond do
        view.locked ->
          UiText.t(view.locale, "cards.metric.not_yet_explored")

        not view.completed and label == view.metric ->
          UiText.t(view.locale, "cards.status.in_progress")

        true ->
          label
      end

    template(
      view: view,
      accent: accent,
      rarity: UiText.t(view.locale, "cards.rarity." <> rarity),
      lines: title_lines(view.name),
      status: status
    )
  end

  def render(view) do
    dir =
      Storage.tmp_dir!(%{root: System.tmp_dir!()}, "achievement-og-" <> Storage.generate_key())

    svg_path = Path.join(dir, "card.svg")
    png_path = Path.join(dir, "card.png")

    try do
      File.write!(svg_path, svg(view))

      executable =
        System.find_executable("rsvg-convert") || raise "Achievement image converter unavailable"

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: ["-f", "png", "-w", "1200", "-h", "630", "-o", png_path, svg_path]
        ])

      try do
        await(port, System.monotonic_time(:millisecond) + 10_000)
        png = File.read!(png_path)

        case png do
          <<137, 80, 78, 71, 13, 10, 26, 10, _::binary-size(8), 1200::32, 630::32, _::binary>> ->
            png

          _ ->
            raise "Achievement image output invalid"
        end
      after
        if Port.info(port), do: Port.close(port)
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp await(port, deadline) do
    receive do
      {^port, {:data, _}} -> await(port, deadline)
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> raise "Achievement image conversion failed"
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "Achievement image conversion timed out"
    end
  end

  defp title_lines(name) do
    lines =
      Enum.reduce(String.split(name), [""], fn word, lines ->
        last = List.last(lines)

        if length(lines) == 1 and last != "" and
             String.length(last) + String.length(word) + 1 > 21,
           do: lines ++ [word],
           else:
             List.replace_at(lines, -1, Enum.join(Enum.reject([last, word], &(&1 == "")), " "))
      end)

    List.update_at(lines, -1, fn line ->
      if String.length(line) > 29, do: String.slice(line, 0, 28) <> "…", else: line
    end)
  end

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
