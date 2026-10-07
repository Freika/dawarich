defmodule Dawarich.Achievements.PublicCard do
  @moduledoc false
  alias Dawarich.Achievements.{Registry, UiPresenter, UiSilhouettes, UiText}
  alias DawarichWeb.Locale

  def load(repo, uuid, context) do
    case query(
           repo,
           "SELECT p.user_id,p.achievement_key,u.settings FROM achievement_progresses p JOIN users u ON u.id=p.user_id AND u.deleted_at IS NULL WHERE p.sharing_uuid=$1 AND p.sharing_enabled=true",
           [uuid]
         ) do
      [[owner_id, key, settings]] ->
        settings = Dawarich.UserSettings.safe(settings)

        cond do
          definition = Registry.find(key) ->
            settings =
              if context[:viewer_id] == owner_id and is_binary(context[:requested_locale]) and
                   is_map(settings),
                 do: Map.put(settings, "locale", context[:requested_locale]),
                 else: settings

            read(repo, owner_id, definition, settings, uuid, context)

          true ->
            :not_found
        end

      [] ->
        :not_found
    end
  end

  defp read(repo, owner_id, definition, settings, uuid, _context) do
    state =
      case query(
             repo,
             "SELECT state FROM achievement_progresses WHERE user_id=$1 AND achievement_key='exploration'",
             [owner_id]
           ) do
        [[state]] -> state
        [] -> %{}
      end

    if supported_settings?(settings, repo) and supported_state?(state) do
      locale = Locale.resolve(nil, %{settings: settings}, %{})
      dates = UiText.local_dates(Map.values(Map.get(state, "earned", %{})), settings)
      progress = UiPresenter.set(definition, state, %{}, locale, dates)
      card = UiPresenter.card(definition, progress, locale)

      shape =
        if definition.kind == "country",
          do: UiSilhouettes.cards(repo, "country", [definition.country])[definition.country],
          else: UiSilhouettes.collection(repo, definition.region_codes, definition.key)

      card = Map.put(card, "silhouette", shape)

      card =
        if progress["locked"],
          do: Map.put(card, "earned_label", UiText.t(locale, "cards.metric.not_yet_explored")),
          else: card

      metric = card["metric_label"]

      {:ok,
       %{
         key: definition.key,
         uuid: uuid,
         locale: locale,
         name: progress["name"],
         count: progress["count"],
         target: progress["target"],
         completed: progress["completed"],
         locked: progress["locked"],
         card: card,
         metric: metric,
         description: UiText.t(locale, "public.social_description", %{"progress" => metric})
       }}
    else
      :handoff
    end
  end

  def supported_settings?(settings, repo) when is_map(settings) do
    raw = settings["timezone"] || System.get_env("TIME_ZONE", "Europe/Berlin")

    is_binary(raw) and
      query(repo, "SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)", [
        Dawarich.TimeZoneName.to_iana(raw)
      ]) == [[true]]
  end

  def supported_settings?(_, _), do: false

  def supported_state?(state) when is_map(state) do
    earned = Map.get(state, "earned", %{})
    celebrated = Map.get(state, "celebrated", %{})

    is_map(earned) and is_map(celebrated) and
      Enum.all?(earned, fn {key, value} -> is_binary(key) and date?(value) end)
  end

  def supported_state?(_), do: false

  defp date?(value) when is_binary(value) do
    if value =~ ~r/\A\d{4}-\d{2}-\d{2}\z/,
      do: match?({:ok, _}, Date.from_iso8601(value)),
      else: match?({:ok, _, _}, DateTime.from_iso8601(value))
  end

  defp date?(_), do: false
  defp query(repo, sql, args), do: repo.query!(sql, args, log: false, prepare: :unnamed).rows
end
