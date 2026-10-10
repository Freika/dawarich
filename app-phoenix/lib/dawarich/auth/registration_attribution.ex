defmodule Dawarich.Auth.RegistrationAttribution do
  @moduledoc false
  @utm ~w(utm_source utm_medium utm_campaign utm_term utm_content)

  def apply(repo, user, params, session, context) do
    values = Enum.map(@utm, &session[&1])

    if Enum.any?(values, &present?/1) do
      assignments =
        @utm |> Enum.with_index(2) |> Enum.map_join(",", fn {key, n} -> "#{key}=$#{n}" end)

      repo.query!("UPDATE users SET " <> assignments <> " WHERE id=$1", [user.id | values],
        log: false
      )
    end

    session = Map.drop(session, @utm)
    {partner, session} = Map.pop(session, "partnero_referral")

    if present?(partner) do
      callback = get_in(context, [:callbacks, :partnero])

      if not is_function(callback, 2) or callback.(user.id, partner) != :ok,
        do: repo.rollback(:partnero_owner)
    end

    if params["signup_intent"] in ["cloud", "self_hosted_demo"] do
      repo.query!(
        "UPDATE users SET settings=COALESCE(settings,'{}'::jsonb) || jsonb_build_object('signup_intent',$2::text) WHERE id=$1",
        [user.id, params["signup_intent"]],
        log: false
      )
    end

    session
  end

  def consume(session), do: Map.drop(session, @utm ++ ["partnero_referral"])

  def store(session, params) do
    session =
      Enum.reduce(@utm, session, fn key, acc ->
        if present?(params[key]), do: Map.put(acc, key, params[key]), else: acc
      end)

    session =
      if present?(params["_gl"]),
        do:
          Map.put(
            session,
            "gads_linker",
            binary_part(params["_gl"], 0, min(byte_size(params["_gl"]), 1024))
          ),
        else: session

    referral =
      Enum.find_value(~w(aff via), fn key -> if present?(params[key]), do: params[key] end)

    if referral,
      do:
        Map.put(
          session,
          "partnero_referral",
          referral |> String.codepoints() |> Enum.take(255) |> Enum.join()
        ),
      else: session
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
