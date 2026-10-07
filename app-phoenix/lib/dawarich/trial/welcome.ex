defmodule Dawarich.Trial.Welcome do
  @moduledoc false
  require Logger
  alias Dawarich.Auth.Trackable
  alias Dawarich.Auth.Recovery.Settings
  alias Dawarich.{I18n, RailsCookies, Repo, UserTimeZone}
  alias Dawarich.Trial.{WelcomeClaim, WelcomeSession, WelcomeToken}
  alias DawarichWeb.{Locale, LocalizedDate, RailsAuth}
  @prefix "controllers.trial.welcome."
  @markers ~w(client aff via referral dawarich_client invitation_token pending_import_ticket)
  @fields ~w(id encrypted_password active_until signup_variant otp_required_for_login provider locked_at settings sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip)

  def prepare(conn, params, context) do
    conn = RailsAuth.call(conn, secret: context.secret, now: clock(context))
    session = conn.assigns.rails_session
    actor = conn.assigns.current_user
    locale = Locale.resolve(params["locale"], actor, session)

    with :ok <- session_state(conn, session, context) do
      case WelcomeToken.decode(
             params["token"],
             context[:jwt_secret],
             DateTime.to_unix(clock(context))
           ) do
        {:ok, claims} ->
          prepare_claim(conn, claims, actor, locale, context)

        {:error, :invalid} ->
          result(
            conn,
            "/users/sign_in",
            "link_invalid_or_expired_please_sign_in",
            locale,
            context
          )

        {:handoff, _} = handoff ->
          handoff
      end
    end
  rescue
    _ -> {:handoff, :issuer}
  end

  def consume(%{result: result}, _context), do: {:ok, result}

  def consume(prepared, context) do
    repo = Map.get(context, :repo, Repo)
    now = DateTime.to_unix(clock(context))

    case WelcomeClaim.claim(prepared.claims["jti"], prepared.claims["exp"], now, repo) do
      :claimed ->
        Logger.info(fn ->
          Jason.encode!(%{
            event: "trial_welcome_consumed",
            user_id: prepared.user.id,
            jti: prepared.claims["jti"],
            variant: prepared.user.signup_variant
          })
        end)

        if prepared.sign_in?, do: track(prepared, context)
        {:ok, %{path: "/map/v2", flash: %{"notice" => prepared.notice}, cookie: prepared.cookie}}

      :consumed when not prepared.sign_in? ->
        {:ok, %{path: "/map/v2", flash: nil, cookie: nil}}

      :consumed ->
        case result(
               prepared.conn,
               "/users/sign_in",
               "this_welcome_link_has_already_been_used",
               prepared.locale,
               context
             ) do
          {:ok, %{result: result}} -> {:ok, result}
          _ -> {:terminal, :issuer}
        end

      {:error, _} ->
        {:terminal, :claim}
    end
  rescue
    _ -> {:terminal, :sign_in}
  end

  defp prepare_claim(conn, claims, actor, locale, context) do
    cond do
      String.trim(claims["jti"]) == "" ->
        result(conn, "/users/sign_in", "link_invalid_please_sign_in", locale, context)

      not WelcomeClaim.supported?(claims["jti"]) ->
        {:handoff, :key}

      true ->
        with {:ok, id} <- user_id(claims["user_id"]) do
          case target(id, context) do
            nil ->
              result(
                conn,
                "/users/sign_in",
                "account_no_longer_exists_please_sign_up_again",
                locale,
                context
              )

            user ->
              prepare_user(conn, claims, user, actor, locale, context)
          end
        end
    end
  end

  defp prepare_user(conn, claims, user, actor, locale, context) do
    if actor && actor.id != user.id do
      result(conn, "/", "another_user_is_already_signed_in", locale, context)
    else
      with :ok <- issuer(user),
           {:ok, settings} <- sanitize(Dawarich.UserSettings.provided(user.settings)) do
        notice = notice(user, actor, locale, context)
        sign_in? = is_nil(actor)
        cookie = cookie(conn, user, notice, context.secret, sign_in?)

        {:ok,
         %{
           claims: claims,
           user: user,
           settings: settings,
           sign_in?: sign_in?,
           notice: notice,
           cookie: cookie,
           locale: locale,
           conn: conn
         }}
      end
    end
  end

  defp session_state(conn, session, context) do
    cookie = conn.cookies["_dawarich_session"]

    cond do
      context[:oidc] == true ->
        {:handoff, :oidc}

      not Dawarich.Standalone.enabled?() and Enum.any?(@markers, &Map.has_key?(session, &1)) ->
        {:handoff, :session}

      not Dawarich.Standalone.enabled?() and
          Enum.any?(Map.keys(session), &String.starts_with?(&1, "devise.")) ->
        {:handoff, :session}

      conn.assigns.rails_locked != nil ->
        {:handoff, :identity}

      Map.has_key?(session, "warden.user.user.key") and is_nil(conn.assigns.current_user) ->
        {:handoff, :identity}

      Map.has_key?(conn.cookies, "remember_user_token") and is_nil(conn.assigns.current_user) ->
        {:handoff, :remember}

      is_binary(cookie) and
          not match?(
            {:ok, %{}},
            RailsCookies.decrypt(cookie, "_dawarich_session", context.secret, clock(context))
          ) ->
        {:handoff, :session}

      true ->
        :ok
    end
  end

  defp user_id(nil), do: {:ok, nil}
  defp user_id(value) when is_number(value), do: {:ok, trunc(value)}

  defp user_id(value) when is_binary(value) do
    case Regex.run(~r/\A[\x09-\x0D ]*([+-]?\d(?:_?\d)*)/, value) do
      [_, number] -> {:ok, String.to_integer(String.replace(number, "_", ""))}
      _ -> {:ok, nil}
    end
  end

  defp user_id(_), do: {:handoff, :identity}

  defp target(nil, _context), do: nil

  defp target(id, context) do
    repo = Map.get(context, :repo, Repo)

    case repo.query!(
           "SELECT " <>
             Enum.join(@fields, ",") <> " FROM users WHERE id=$1 AND deleted_at IS NULL",
           [id],
           log: false
         ).rows do
      [row] -> Map.new(Enum.zip(Enum.map(@fields, &String.to_existing_atom/1), row))
      [] -> nil
    end
  end

  defp issuer(user) do
    cond do
      user.otp_required_for_login or user.provider not in [nil, ""] or not is_nil(user.locked_at) ->
        {:handoff, :account}

      not is_binary(user.encrypted_password) or byte_size(user.encrypted_password) < 29 ->
        {:handoff, :salt}

      not is_nil(user.signup_variant) and
          (not is_binary(user.signup_variant) or byte_size(user.signup_variant) > 128) ->
        {:handoff, :account}

      true ->
        :ok
    end
  end

  defp sanitize(settings) do
    case Settings.sanitize(settings) do
      {:ok, settings} -> {:ok, settings}
      _ -> {:handoff, :settings_callback}
    end
  end

  defp cookie(conn, user, notice, secret, sign_in?),
    do: WelcomeSession.cookie(conn, user, notice, secret, sign_in?)

  defp result(conn, path, key, locale, context),
    do: WelcomeSession.result(conn, path, key, locale, context)

  defp notice(%{active_until: nil}, _actor, locale, _context) do
    {:ok, notice} = I18n.t(locale, @prefix <> "trial_activating")
    notice
  end

  defp notice(user, actor, locale, context) do
    env = Map.get(context, :env, System.get_env())

    settings =
      if actor,
        do: Dawarich.UserSettings.get(actor),
        else: %{"timezone" => env["TIME_ZONE"] || "Europe/Berlin"}

    date = UserTimeZone.local(settings, naive(user.active_until)).local |> NaiveDateTime.to_date()

    {:ok, notice} =
      I18n.t(locale, @prefix <> "trial_active_until", %{
        "date" => LocalizedDate.l(locale, date, "long")
      })

    notice
  end

  defp track(prepared, context) do
    repo = Map.get(context, :repo, Repo)
    user = Map.update!(prepared.user, :current_sign_in_at, &utc/1)
    ip = :inet.ntoa(prepared.conn.remote_ip) |> to_string()
    changes = Trackable.changes(user, clock(context), ip)

    result =
      repo.query!(
        "UPDATE users SET sign_in_count=$1,current_sign_in_at=$2,last_sign_in_at=$3,current_sign_in_ip=$4,last_sign_in_ip=$5,updated_at=$2,settings=$6 WHERE id=$7 AND deleted_at IS NULL",
        [
          changes.sign_in_count,
          naive(changes.current_sign_in_at),
          naive(changes.last_sign_in_at),
          changes.current_sign_in_ip,
          changes.last_sign_in_ip,
          prepared.settings,
          user.id
        ],
        log: false
      )

    if result.num_rows != 1, do: raise("welcome target unavailable")
  end

  defp naive(%DateTime{} = time), do: DateTime.to_naive(time)
  defp naive(time), do: time
  defp utc(nil), do: nil
  defp utc(%NaiveDateTime{} = time), do: DateTime.from_naive!(time, "Etc/UTC")
  defp utc(time), do: time
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
end
