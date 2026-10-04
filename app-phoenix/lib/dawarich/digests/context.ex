defmodule Dawarich.Digests.Context do
  @moduledoc false

  alias Dawarich.{Entitlements, TimeZoneName}

  defmodule UserNotFound do
    defexception [:message]
  end

  def load!(repo, user_id, opts \\ []) do
    user = user!(repo, user_id)
    env = Keyword.get(opts, :env, System.get_env())
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    ambient = Keyword.get(opts, :ambient_zone, env["TIME_ZONE"] || "Europe/Berlin")
    ambient_zone = resolve(repo, ambient) || raise(ArgumentError, "Invalid Timezone: #{ambient}")
    raw = user.settings["timezone"]
    effective = raw || env["TIME_ZONE"] || "UTC"

    context = %{
      user_id: user.id,
      user: user,
      settings: user.settings,
      raw_zone: raw,
      effective_zone: effective,
      user_zone: resolve(repo, effective),
      time_of_day_zone: resolve(repo, effective) || "Etc/UTC",
      ambient_zone: ambient_zone,
      now: now,
      env: env,
      restricted?:
        not Entitlements.full_access?(
          repo,
          user,
          DawarichWeb.LayoutAssigns.self_hosted?(env),
          now
        )
    }

    window(repo, context, ambient_zone)
  end

  def window(_repo, %{restricted?: false} = context, zone),
    do: Map.merge(context, %{window_zone: zone, cutoff: nil, stat_cutoff: nil, point_cutoff: nil})

  def window(repo, context, zone) do
    %{rows: [[cutoff, date]]} =
      repo.query!(
        "SELECT (wall - interval '1 year') AT TIME ZONE $2, (wall - interval '1 year')::date " <>
          "FROM (SELECT $1::timestamptz AT TIME ZONE $2 AS wall) x",
        [context.now, zone],
        log: false
      )

    Map.merge(context, %{
      window_zone: zone,
      cutoff: cutoff,
      stat_cutoff: {date.year, date.month},
      point_cutoff: DateTime.to_unix(cutoff)
    })
  end

  defp user!(repo, user_id) do
    case repo.query!(
           "SELECT id, settings, plan FROM public.users WHERE id = $1 AND deleted_at IS NULL",
           [user_id],
           log: false
         ).rows do
      [[id, settings, plan]] ->
        %{id: id, settings: if(is_map(settings), do: settings, else: %{}), plan: plan}

      [] ->
        raise UserNotFound,
          message:
            "Couldn't find User with 'id'=#{user_id} [WHERE \"users\".\"deleted_at\" IS NULL]"
    end
  end

  defp resolve(repo, raw) when is_binary(raw) do
    case repo.query!(
           "SELECT name FROM pg_timezone_names WHERE name = $1",
           [TimeZoneName.to_iana(raw)],
           log: false
         ).rows do
      [[name] | _] -> name
      [] -> nil
    end
  end

  defp resolve(_repo, _raw), do: nil
end
