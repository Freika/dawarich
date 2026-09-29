defmodule Dawarich.Achievements.Notices do
  @moduledoc false

  alias Dawarich.Achievements.Registry

  @region_notify_cap 5

  def award_and_notify(repo, user_id, settings, progress_id, newly, notify) do
    %{rows: [[state]]} =
      repo.query!("SELECT state FROM achievement_progresses WHERE id = $1", [progress_id],
        log: false
      )

    earned = Map.get(state, "earned", %{})

    awarded =
      repo.query!("SELECT achievement_key FROM user_achievements WHERE user_id = $1", [user_id],
        log: false
      ).rows
      |> MapSet.new(&hd/1)

    completed = Enum.filter(Registry.all(), &award?(repo, user_id, &1, earned, awarded, notify))

    if notify do
      locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)
      notify_regions(repo, user_id, locale, newly, earned)

      for definition <- completed,
          definition.kind != "region_set",
          do: notify_completion(repo, user_id, locale, definition)
    end

    :ok
  end

  def unlock_geographies!(repo, user_id, codes) do
    case Enum.filter(codes, &Registry.visible_geography?/1) do
      [] ->
        :ok

      visible ->
        repo.query!(
          "INSERT INTO achievement_unlock_events (user_id, kind, key, created_at, updated_at) " <>
            "SELECT $1, 'geography', code, now(), now() FROM unnest($2::text[]) AS code " <>
            "ON CONFLICT (user_id, kind, key) DO NOTHING",
          [user_id, visible],
          log: false
        )

        :ok
    end
  end

  defp award?(repo, user_id, definition, earned, awarded, notify) do
    if MapSet.member?(awarded, definition.key) or
         earned_count(definition, earned) < definition.target do
      false
    else
      {:ok, created?} =
        repo.transaction(fn ->
          case repo.query!(
                 "INSERT INTO user_achievements (user_id, achievement_key, earned_at, metadata, created_at, updated_at) " <>
                   "VALUES ($1, $2, now(), '{}', now(), now()) " <>
                   "ON CONFLICT (user_id, achievement_key) DO NOTHING RETURNING id",
                 [user_id, definition.key],
                 log: false
               ).rows do
            [[_id]] ->
              if notify and definition.kind != "region_set" and not definition.flat do
                repo.query!(
                  "INSERT INTO achievement_unlock_events (user_id, kind, key, created_at, updated_at) " <>
                    "VALUES ($1, 'set', $2, now(), now()) ON CONFLICT (user_id, kind, key) DO NOTHING",
                  [user_id, definition.key],
                  log: false
                )
              end

              true

            [] ->
              false
          end
        end)

      created?
    end
  end

  defp earned_count(definition, earned),
    do: Enum.count(definition.region_codes, &Map.has_key?(earned, &1))

  defp notify_regions(repo, user_id, locale, newly, earned) do
    if length(newly) > @region_notify_cap do
      notify!(
        repo,
        user_id,
        locale,
        {"digest_title", %{"count" => length(newly)}},
        {"digest_content", %{}}
      )
    else
      for code <- newly, definition = Registry.announcer(code), definition != nil do
        content = if definition.level == "country", do: "country_content", else: "region_content"

        notify!(
          repo,
          user_id,
          locale,
          {"region_title", %{"region" => definition.regions[code]}},
          {content,
           %{
             "achievement" => name(definition, locale),
             "count" => min(earned_count(definition, earned), definition.target),
             "total" => definition.target
           }}
        )
      end
    end
  end

  defp notify_completion(repo, user_id, locale, definition) do
    content =
      if definition.flat do
        {"completion_country", %{}}
      else
        unit = if definition.level == "country", do: "countries", else: "regions"
        quantifier = if definition.threshold, do: "target", else: "all"

        {"completion_#{quantifier}_#{unit}",
         %{"count" => definition.threshold || definition.total}}
      end

    notify!(
      repo,
      user_id,
      locale,
      {"completion_title", %{"achievement" => name(definition, locale)}},
      content
    )
  end

  defp notify!(
         repo,
         user_id,
         locale,
         {title_key, title_bindings},
         {content_key, content_bindings}
       ) do
    Dawarich.Notifications.create!(
      repo,
      user_id,
      :info,
      text!(locale, title_key, title_bindings),
      text!(locale, content_key, content_bindings)
    )
  end

  defp name(definition, locale), do: definition.names[locale] || definition.names["en"]

  defp text!(locale, key, bindings) do
    case Dawarich.I18n.t(locale, "achievements.notifications." <> key, bindings) do
      {:ok, text} when is_binary(text) ->
        text

      other ->
        raise "no translation for #{locale}.achievements.notifications.#{key}: #{inspect(other)}"
    end
  end
end
