defmodule Dawarich.Auth.AccountLink.Closure do
  @moduledoc false
  import Plug.Conn
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Api.ChallengeToken
  alias Dawarich.Auth.AccountLink.SignIn
  alias Dawarich.Auth.Providers.{Accounts, Completion, Failure, Jwks}
  alias Dawarich.{RailsCache.Wire, Redis, Repo}
  alias DawarichWeb.AuthAccountLink.Response

  def issue(id, provider, uid, context) do
    with {:ok, secret} <- ChallengeToken.secret(context) do
      now = epoch(context)

      payload = %{
        "user_id" => id,
        "provider" => provider,
        "uid" => uid,
        "purpose" => "oauth_account_link",
        "jti" => Ecto.UUID.generate(),
        "iat" => now,
        "exp" => now + 900
      }

      input = encode(%{"alg" => "HS256"}) <> "." <> encode(payload)

      {:ok,
       input <>
         "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, secret, input), padding: false)}
    else
      _ -> {:error, :secret}
    end
  end

  def confirm(token, session, context) do
    with {:ok, claims} <- verify(token, context),
         {:ok, nil} <- command(["GET", key(claims["jti"])], context) do
      repo = Map.get(context, :repo, Repo)

      case repo.transaction(fn ->
             user =
               repo.one(
                 from(u in Account,
                   where: u.id == ^claims["user_id"] and is_nil(u.deleted_at),
                   lock: "FOR UPDATE"
                 ),
                 log: false
               )

             cond do
               is_nil(user) ->
                 {:error, :invalid_token}

               user.provider not in [nil, ""] and
                   (user.provider != claims["provider"] or user.uid != claims["uid"]) ->
                 {:error, :different_identity}

               not consume(claims["jti"], context) ->
                 {:error, :replayed}

               true ->
                 link(user, claims, session, context)
             end
           end) do
        {:ok, result} -> result
        _ -> {:error, :save_failed}
      end
    else
      {:ok, _} -> {:error, :replayed}
      error -> error
    end
  rescue
    _ -> {:error, :save_failed}
  end

  def pending(session, context) do
    pending = session["pending_oauth_link"]

    with true <- is_map(pending),
         expires when is_integer(expires) <- pending["expires_at"],
         true <- expires >= epoch(context),
         id when is_integer(id) <- pending["user_id"],
         user when not is_nil(user) <- Map.get(context, :repo, Repo).get(Account, id, log: false),
         true <- is_nil(user.deleted_at) do
      {:ok, %{user: user, pending: pending, session: session}}
    else
      _ -> {:error, :no_pending_link}
    end
  end

  def password(session, password, context) do
    with {:ok, prepared} <- pending(session, context) do
      if is_binary(password) and password != "" and
           Bcrypt.verify_pass(
             binary_part(password, 0, min(byte_size(password), 72)),
             prepared.user.encrypted_password
           ) do
        link(prepared.user, prepared.pending, session, context)
      else
        count = (session["pending_oauth_link_attempts"] || 0) + 1

        if count >= 5,
          do: {:error, :too_many_attempts, clear(session)},
          else:
            {:error, :incorrect_password, Map.put(session, "pending_oauth_link_attempts", count)}
      end
    end
  end

  defp link(user, pending, session, context) do
    repo = Map.get(context, :repo, Repo)

    user =
      repo.update!(
        Ecto.Changeset.change(user, %{
          provider: pending["provider"],
          uid: pending["uid"],
          updated_at: clock(context)
        }),
        log: false
      )

    kind = if user.otp_required_for_login, do: :link_only, else: :sign_in

    if kind == :sign_in and not Dawarich.Accounts.unlocked?(user, clock(context)) do
      {:error, :locked}
    else
      {:ok, result} =
        SignIn.commit(
          %{user: user, pending: pending, session: clear(session), kind: kind},
          context
        )

      session =
        if kind == :sign_in,
          do: Completion.claim(repo, user, result.session, context),
          else: result.session

      {:ok, %{result | session: session}}
    end
  end

  def route(%{method: "GET", request_path: "/auth/account_link"} = conn, params, context) do
    case confirm(params["token"], conn.assigns.rails_session, context) do
      {:ok, result} -> completed(conn, result, context)
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(%{method: "GET", request_path: "/auth/account_link/challenge"} = conn, _, context) do
    case pending(conn.assigns.rails_session, context) do
      {:ok, prepared} -> Response.form(conn, labeled(prepared, context), context)
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(
        %{method: "POST", request_path: "/auth/account_link/challenge"} = conn,
        params,
        context
      ) do
    case password(conn.assigns.rails_session, params["password"], context) do
      {:ok, result} ->
        completed(conn, result, context)

      {:error, :incorrect_password, session} ->
        {:ok, prepared} = pending(session, context)
        conn = assign(conn, :rails_session, flash(session, "incorrect_password", %{}, context))

        conn = register_before_send(conn, &%{&1 | status: 422})

        Response.form(
          conn,
          labeled(%{prepared | session: conn.assigns.rails_session}, context),
          context
        )

      {:error, reason, session} ->
        error(assign(conn, :rails_session, session), reason, context)

      {:error, reason} ->
        error(conn, reason, context)
    end
  end

  def route(%{method: "POST", request_path: "/auth/account_link/email"} = conn, _, context) do
    with {:ok, prepared} <- pending(conn.assigns.rails_session, context) do
      label =
        prepared.pending["provider_label"] ||
          Accounts.label(prepared.pending["provider"], context)

      case Accounts.send_link(
             prepared.user,
             prepared.pending["provider"],
             prepared.pending["uid"],
             label,
             context
           ) do
        {:ok, :sent} ->
          Failure.redirect(
            conn,
            "/users/sign_in",
            "controllers.auth.account_links.confirmation_link_sent",
            %{"email" => prepared.user.email},
            context,
            "notice"
          )

        {:error, {:rate_limited, _}} ->
          error(conn, :rate_limited, context)

        {:error, _} ->
          Failure.terminal(conn)
      end
    else
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(conn, _, _), do: conn |> send_resp(404, "") |> halt()

  defp completed(conn, result, context) do
    result = labeled(result, context)
    Response.completed(conn, result, context)
  end

  defp labeled(result, context) do
    pending =
      Map.put_new(
        result.pending,
        "provider_label",
        Accounts.label(result.pending["provider"], context)
      )

    %{result | pending: pending}
  end

  defp error(conn, reason, context), do: Failure.link_error(conn, reason, context)

  defp flash(session, key, bindings, context) do
    text =
      DawarichWeb.Translate.t(context.locale, "controllers.auth.account_links." <> key, bindings)

    Map.put(session, "flash", %{"discard" => [], "flashes" => %{"alert" => text}})
  end

  defp verify(token, context) when is_binary(token) and byte_size(token) <= 16384 do
    with {:ok, secret} <- ChallengeToken.secret(context),
         [header, payload, signed] <- String.split(token, "."),
         {:ok, signature} <- Base.url_decode64(signed, padding: false),
         true <-
           Plug.Crypto.secure_compare(
             signature,
             :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload)
           ),
         {:ok, %{"alg" => "HS256"}} <- Jwks.decode(header),
         {:ok, claims} when is_map(claims) <- Jwks.decode(payload),
         true <- claims["purpose"] == "oauth_account_link",
         true <- is_binary(claims["jti"]) and String.trim(claims["jti"]) != "",
         true <- is_integer(claims["exp"]) and claims["exp"] > epoch(context),
         true <-
           is_nil(claims["iat"]) or
             (is_integer(claims["iat"]) and epoch(context) - claims["iat"] <= 900),
         true <- is_integer(claims["user_id"]),
         true <- is_binary(claims["provider"]) and claims["provider"] != "",
         true <- is_binary(claims["uid"]) and claims["uid"] != "" do
      {:ok, claims}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp verify(_, _), do: {:error, :invalid_token}

  defp consume(jti, context) do
    bytes = Wire.encode_boolean(true, expires_at: epoch(context) + 900)
    command(["SET", key(jti), bytes, "NX", "PX", "900000"], context) == {:ok, "OK"}
  end

  defp key(jti), do: "oauth_account_link:consumed:" <> jti
  defp command(args, context), do: Map.get(context, :cache_command, &Redis.cache_command/1).(args)
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
  defp epoch(context), do: DateTime.to_unix(clock(context))
  defp clear(session), do: Map.drop(session, ~w(pending_oauth_link pending_oauth_link_attempts))
  defp encode(value), do: Jason.encode!(value) |> Base.url_encode64(padding: false)
end
