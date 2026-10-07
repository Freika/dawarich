defmodule Dawarich.Mail.FamilyLapseWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, ExploreFeatures, Wave2}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @handler "mail.family_lapse"

  @pending """
  SELECT 1 FROM phoenix.delivery_claims
  WHERE handler = $1 AND provider_key = $2 AND event_id = $3 AND delivered_at IS NULL
  """

  @payload %{
    "user_id" => :integer,
    "family_id" => :integer,
    "locale" => :string,
    "lapse_at" => :string
  }

  @lock """
  SELECT u.email, u.settings, f.name, o.email
  FROM users u JOIN families f ON f.id = $2
  LEFT JOIN users o ON o.id = f.creator_id AND o.deleted_at IS NULL
  WHERE u.id = $1 AND u.deleted_at IS NULL
  FOR UPDATE OF u
  """

  @mark """
  UPDATE users SET settings = jsonb_set(jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}',
    COALESCE(settings->'family', '{}'::jsonb), true), '{family,plan_lapse_notified_at}', to_jsonb($2::text), true),
    updated_at = $3 WHERE id = $1
  """

  @clear """
  UPDATE users SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}',
    COALESCE(settings->'family', '{}'::jsonb) - 'plan_lapse_notified_at'), updated_at = $2
  WHERE id = $1 AND settings->'family'->>'plan_lapse_notified_at' IS NOT NULL
  """

  def args_from_command(1, payload) when is_map(payload) do
    with {:ok, user_id} <- id(Map.get(payload, "user_id")),
         {:ok, family_id} <- id(Map.get(payload, "family_id")) do
      Wave2.decode(
        1,
        payload |> Map.put("user_id", user_id) |> Map.put("family_id", family_id),
        @payload
      )
    end
  end

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  defp id(value)
       when is_integer(value) and value in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
       do: {:ok, value}

  defp id(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> id(integer)
      _ -> {:error, "invalid_payload"}
    end
  end

  defp id(_value), do: {:error, "invalid_payload"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "family_id" => family_id} = args}) do
    repo = Dawarich.Jobs.repo()
    event_id = args["event_id"]

    case claim(repo, user_id, family_id, event_id) do
      {:ok, {key, [email, settings, family, owner_email]}} ->
        locale = ExploreFeatures.locale(settings, args["locale"])

        send_notice(repo, user_id, fn env ->
          with {:ok, message} <- Wave2.family_lapse(email, locale, family, owner_email, env),
               id = Delivery.message_id(@handler, dedupe_key(args), event_id, env),
               :ok <- transport().deliver(Map.put(message, :message_id, id), env),
               do: Delivery.delivered!(repo, @handler, key, event_id)
        end)

      {:error, _skipped} ->
        :ok
    end
  end

  defp claim(repo, user_id, family_id, event_id) do
    repo.transaction(fn ->
      case repo.query!(@lock, [user_id, family_id], log: false).rows do
        [[_email, settings | _] = row] ->
          notified_at = notified_at(settings)

          cond do
            not Ruby.present?(notified_at) ->
              {mark!(repo, user_id, event_id), row}

            is_binary(notified_at) and pending?(repo, key(user_id, notified_at), event_id) ->
              {key(user_id, notified_at), row}

            true ->
              repo.rollback(:notified)
          end

        [] ->
          repo.rollback(:missing)
      end
    end)
  end

  defp mark!(repo, user_id, event_id) do
    marked_at =
      case repo.query!(
             "SELECT provider_key FROM phoenix.delivery_claims WHERE handler=$1 AND event_id=$2",
             [@handler, Ecto.UUID.dump!(event_id)],
             log: false
           ).rows do
        [[previous]] -> String.replace_prefix(previous, "family-lapse:#{user_id}:", "")
        [] -> DateTime.utc_now() |> DateTime.to_iso8601()
      end

    repo.query!(@mark, [user_id, marked_at, NaiveDateTime.utc_now()], log: false)
    :send = Delivery.claim(repo, @handler, key(user_id, marked_at), event_id)
    key(user_id, marked_at)
  end

  defp pending?(repo, key, event_id),
    do: repo.query!(@pending, [@handler, key, Ecto.UUID.dump!(event_id)], log: false).rows != []

  defp key(user_id, notified_at), do: "family-lapse:#{user_id}:#{notified_at}"

  defp dedupe_key(args),
    do: "family-lapse:#{args["family_id"]}:#{args["user_id"]}:#{args["lapse_at"]}"

  defp send_notice(repo, user_id, send) do
    case send.(System.get_env()) do
      :ok ->
        :ok

      {:error, reason} ->
        clear!(repo, user_id)
        {:error, reason}
    end
  rescue
    exception ->
      clear!(repo, user_id)
      reraise exception, __STACKTRACE__
  end

  defp clear!(repo, user_id),
    do: repo.query!(@clear, [user_id, NaiveDateTime.utc_now()], log: false)

  defp notified_at(%{"family" => %{} = family}), do: family["plan_lapse_notified_at"]
  defp notified_at(_settings), do: nil

  defp transport, do: Application.get_env(:dawarich, :mail_transport, Dawarich.Mail.Smtp)
end
