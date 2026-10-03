defmodule Dawarich.Auth.Recovery.Flow do
  @moduledoc false
  alias Dawarich.Auth.{Admission, SessionCookie}
  alias Dawarich.Auth.Recovery.{Lifecycle, Token}
  alias Dawarich.{RailsCookies, RailsSecret}

  def dispatch(method, path, params, session, context \\ %{}) do
    with true <- Map.get(context, :enabled, false) == true,
         :ok <-
           Admission.context(
             session,
             Map.get(context, :headers, []),
             Map.get(context, :oidc, true),
             Map.get(context, :self_hosted, false)
           ),
         false <- Map.has_key?(session, "warden.user.user.key"),
         :ok <- parameters(params) do
      action(method, path, params, session, context)
    else
      _ -> {:handoff, :context}
    end
  end

  defp action("GET", "/users/password/new", _, session, _),
    do: render(:password_new, 200, session)

  defp action("GET", "/users/unlock/new", _, session, _), do: render(:unlock_new, 200, session)

  defp action("GET", "/users/password/edit", params, session, context) do
    if Token.blank?(params["reset_password_token"]) do
      redirect(
        302,
        "/users/sign_in",
        flash(session, "alert", text(context, "devise.passwords.no_token"))
      )
    else
      render(:password_edit, 200, session, %{token: params["reset_password_token"]})
    end
  end

  defp action("POST", "/users/password", params, session, context),
    do: request(:reset, params, session, context)

  defp action("POST", "/users/unlock", params, session, context),
    do: request(:unlock, params, session, context)

  defp action("PUT", "/users/password", params, session, context) do
    if is_binary(context[:sign_in_ip]) do
      case Lifecycle.reset(
             params["user[reset_password_token]"],
             params["user[password]"],
             params["user[password_confirmation]"],
             context
           ) do
        {:ok, user} ->
          {next, cookie} =
            SessionCookie.for_login(
              session,
              user,
              text(context, "devise.passwords.updated"),
              secret(context)
            )

          {:ok, %{status: 303, location: return_to(session), session: next, cookie: cookie}}

        {:error, error} ->
          render(:password_edit, 422, session, %{
            error: error,
            token: params["user[reset_password_token]"]
          })

        other ->
          other
      end
    else
      {:handoff, :client_ip}
    end
  end

  defp action("GET", "/users/unlock", params, session, context) do
    case Lifecycle.unlock(params["unlock_token"], context) do
      {:ok, _} ->
        redirect(
          302,
          "/users/sign_in",
          flash(session, "notice", text(context, "devise.unlocks.unlocked"))
        )

      {:error, error} ->
        render(:unlock_new, 200, session, %{error: error})

      other ->
        other
    end
  end

  defp action(_, _, _, _, _), do: {:handoff, :route}

  defp request(kind, params, session, context) do
    case context[:enqueue] do
      enqueue when is_function(enqueue, 1) or is_function(enqueue, 2) ->
        result =
          if kind == :reset,
            do: Lifecycle.request_reset(params["user[email]"], context),
            else: Lifecycle.request_unlock(params["user[email]"], context)

        case result do
          {:ok, %{user: user, notification: notification}} ->
            delivery =
              if is_function(enqueue, 2),
                do: enqueue.(notification, user),
                else: enqueue.(notification)

            case delivery do
              :ok -> requested(kind, session, context)
              error -> {:error, {:delivery, error}}
            end

          {:error, error} when error in [:not_found, :not_locked] ->
            requested(kind, session, context)

          other ->
            other
        end

      _ ->
        {:handoff, :delivery_owner}
    end
  end

  defp requested(kind, session, context) do
    scope = if kind == :reset, do: "passwords", else: "unlocks"

    redirect(
      303,
      "/users/sign_in",
      flash(session, "notice", text(context, "devise.#{scope}.send_paranoid_instructions"))
    )
  end

  def encode_session(session, context),
    do: RailsCookies.encrypt(session, "_dawarich_session", secret(context))

  defp flash(session, kind, value),
    do: Map.put(session, "flash", %{"discard" => [], "flashes" => %{kind => value}})

  defp redirect(status, path, session),
    do: {:ok, %{status: status, location: path, session: session}}

  defp render(view, status, session, assigns \\ %{}),
    do: {:ok, %{status: status, location: nil, session: session, view: view, assigns: assigns}}

  defp text(context, key) do
    {:ok, value} = Dawarich.I18n.t(Map.get(context, :locale, "en"), key)
    value
  end

  defp return_to(%{"user_return_to" => "/" <> rest = path}) do
    if String.starts_with?(rest, "/") or String.contains?(path, ["\\", "\r", "\n"]),
      do: "/",
      else: path
  end

  defp return_to(_), do: "/"
  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)

  defp parameters(params) when is_map(params) do
    allowed =
      ~w(authenticity_token commit utf8 _method user[email] user[password] user[password_confirmation] user[reset_password_token] reset_password_token unlock_token)

    if Enum.all?(params, fn {key, value} ->
         key in allowed and
           (is_nil(value) or
              (is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)))
       end),
       do: :ok,
       else: {:handoff, :parameters}
  end

  defp parameters(_), do: {:handoff, :parameters}
end
