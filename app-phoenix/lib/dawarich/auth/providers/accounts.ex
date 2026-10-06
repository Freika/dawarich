defmodule Dawarich.Auth.Providers.Accounts do
  @moduledoc false
  alias Dawarich.Auth.{Account, AccountLink.Closure}
  alias Dawarich.Auth.Providers.Conflicts
  alias Dawarich.{RailsCache.Wire, Redis, Repo}

  def resolve(identity, context) do
    identity = %{
      identity
      | uid: to_string(identity.uid || ""),
        email: String.downcase(identity.email || "")
    }

    case Conflicts.identity(identity.provider, identity.uid, context) do
      nil ->
        case Conflicts.email(identity.email, context) do
          nil ->
            if Map.get(context, :allow_registration, true),
              do: create(identity, context),
              else: {:ok, nil, false}

          user ->
            collision(user, identity, context)
        end

      user ->
        Conflicts.account(user, false)
    end
  end

  def collision(%{deleted_at: deleted}, _, _) when not is_nil(deleted),
    do: {:error, :pending_deletion}

  def collision(user, identity, context) do
    if identity.email_verified do
      case Map.get(context, :on_email_collision, :send_email) do
        :raise_only ->
          {:link_required,
           %{
             user: user,
             provider: identity.provider,
             uid: identity.uid,
             rate_limited: false,
             retry_after: nil
           }}

        :send_email ->
          case send_link(
                 user,
                 identity.provider,
                 identity.uid,
                 label(identity.provider, context),
                 context
               ) do
            {:ok, :sent} ->
              {:link_required,
               %{
                 user: user,
                 provider: identity.provider,
                 uid: identity.uid,
                 rate_limited: false,
                 retry_after: nil
               }}

            {:error, {:rate_limited, retry}} ->
              {:link_required,
               %{
                 user: user,
                 provider: identity.provider,
                 uid: identity.uid,
                 rate_limited: true,
                 retry_after: retry
               }}

            other ->
              other
          end
      end
    else
      {:error, :unverified_email}
    end
  end

  def send_link(user, provider, uid, label, context) do
    case context[:enqueue_link] do
      enqueue when is_function(enqueue, 1) ->
        with {:ok, :acquired} <- acquire(user.id, context),
             {:ok, token} <- Closure.issue(user.id, provider, uid, context) do
          now = epoch(context)

          payload = %{
            "user_id" => user.id,
            "locale" => Map.get(context, :locale, "en"),
            "provider_label" => label,
            "link_url" =>
              context.base_url <> "/auth/account_link?" <> URI.encode_query(%{"token" => token}),
            "link_token_sha256" => Base.encode16(:crypto.hash(:sha256, token), case: :lower),
            "link_expires_at" => now + 900
          }

          if enqueue.(payload) == :ok, do: {:ok, :sent}, else: {:error, :mail_owner}
        end

      _ ->
        {:error, :mail_owner}
    end
  end

  def acquire(id, context) do
    now = epoch(context)
    bytes = integer_entry(now, now + 3600)
    key = "oauth_account_link:rate_limit:#{id}"

    case command(["SET", key, bytes, "NX", "PX", "3600000"], context) do
      {:ok, "OK"} ->
        {:ok, :acquired}

      {:ok, nil} ->
        retry =
          case command(["GET", key], context) do
            {:ok, value} ->
              case Wire.decode(value) do
                {:ok, %{value: sent}} when is_integer(sent) ->
                  min(3600, max(1, 3600 - (now - sent)))

                _ ->
                  3600
              end

            _ ->
              3600
          end

        {:error, {:rate_limited, retry}}

      _ ->
        {:error, :cache}
    end
  end

  def label("github", _), do: "GitHub"
  def label(provider, _) when provider in ["google", "google_oauth2"], do: "Google"
  def label("apple", _), do: "Sign in with Apple"

  def label("openid_connect", context),
    do: Map.get(context, :provider_name, System.get_env("OIDC_PROVIDER_NAME", "Openid Connect"))

  def label(provider, _), do: String.capitalize(provider)

  defp create(%{email: "", provider: "apple"}, _), do: {:error, :missing_email}

  defp create(identity, context) do
    repo = Map.get(context, :repo, Repo)
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    email =
      if identity.email == "",
        do: "#{identity.uid}@#{identity.provider}.dawarich.app",
        else: Account.normalize_email(identity.email)

    password =
      Bcrypt.hash_pwd_salt(Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        log_rounds: Map.get(context, :log_rounds, 12)
      )

    self_hosted = Map.get(context, :self_hosted, System.get_env("SELF_HOSTED", "true") != "false")
    until = if self_hosted, do: active_until(now)
    if is_function(context[:before_insert], 0), do: context.before_insert.()

    rows =
      repo.query!(
        "INSERT INTO users(email,encrypted_password,api_key,first_name,last_name,provider,uid,status,plan,active_until,signup_variant,settings,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,1,$9,$10,'{\"fog_of_war_meters\":\"100\",\"meters_between_routes\":\"500\",\"minutes_between_routes\":\"30\"}'::jsonb,$11,$11) ON CONFLICT DO NOTHING RETURNING id",
        [
          email,
          password,
          Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
          identity[:first_name],
          identity[:last_name],
          identity.provider,
          identity.uid,
          if(self_hosted, do: 1, else: 3),
          until,
          nil,
          DateTime.to_naive(now)
        ],
        log: false
      ).rows

    case rows do
      [[id]] ->
        {:ok, repo.get!(Account, id, log: false), true}

      [] ->
        case Conflicts.identity(identity.provider, identity.uid, context) do
          nil ->
            case Conflicts.email(email, context) do
              nil -> {:error, :account_creation_failed}
              user -> collision(user, identity, context)
            end

          user ->
            Conflicts.account(user, false)
        end
    end
  end

  defp active_until(now) do
    year = now.year + 1000
    date = Date.new!(year, now.month, min(now.day, Calendar.ISO.days_in_month(year, now.month)))
    DateTime.add(now, Date.diff(date, DateTime.to_date(now)) * 86400) |> DateTime.to_naive()
  end

  defp integer_entry(value, expires) do
    bytes = :binary.encode_unsigned(value, :little)

    <<0, 17, 1, expires * 1.0::little-float-64, -1::little-signed-32, 4, 8, ?i, byte_size(bytes),
      bytes::binary>>
  end

  defp command(args, context), do: Map.get(context, :cache_command, &Redis.cache_command/1).(args)
  defp epoch(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
end
