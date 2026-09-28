defmodule Dawarich.Mail.FamilyLapseWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{ExploreFeatures, Wave2}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

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

  def args_from_command(version, payload), do: Wave2.decode(version, payload, @payload)

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "family_id" => family_id} = args}) do
    repo = Dawarich.Jobs.repo()

    case claim(repo, user_id, family_id) do
      {:ok, [email, settings, family, owner_email]} ->
        locale = ExploreFeatures.locale(settings, args["locale"])

        send_notice(repo, user_id, fn env ->
          Wave2.family_lapse(email, locale, family, owner_email, env)
        end)

      {:error, _skipped} ->
        :ok
    end
  end

  defp claim(repo, user_id, family_id) do
    repo.transaction(fn ->
      case repo.query!(@lock, [user_id, family_id], log: false).rows do
        [[_email, settings | _] = row] ->
          if Ruby.present?(notified_at(settings)),
            do: repo.rollback(:notified),
            else: mark!(repo, user_id, row)

        [] ->
          repo.rollback(:missing)
      end
    end)
  end

  defp mark!(repo, user_id, row) do
    marked_at = DateTime.utc_now() |> DateTime.to_iso8601()
    repo.query!(@mark, [user_id, marked_at, NaiveDateTime.utc_now()], log: false)
    row
  end

  defp send_notice(repo, user_id, build) do
    env = System.get_env()

    with {:ok, message} <- build.(env),
         :ok <- transport().deliver(message, env) do
      :ok
    else
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
