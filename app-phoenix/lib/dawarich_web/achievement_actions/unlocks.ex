defmodule DawarichWeb.AchievementActions.Unlocks do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Achievements.{Deck, UnlockCard}
  alias DawarichWeb.{AchievementUnlockReveal, Locale, RailsProxy}
  alias DawarichWeb.AchievementActions.{Gate, Request, Response}

  def init(opts), do: opts

  def call(conn, opts) do
    action = Keyword.get_lazy(opts, :action, fn -> action(conn) end)

    case Request.load(conn, action, opts) do
      {:ok, conn, actor, params, context} ->
        if Response.supported?(conn),
          do: execute(conn, actor, params, context),
          else: handoff(conn, opts)

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        handoff(conn, opts)
    end
  end

  defp action(conn) do
    Enum.find([:next, :seen, :dismiss], fn action ->
      match?({:ok, _}, Gate.route(conn, action))
    end)
  end

  defp execute(conn, actor, params, context) do
    conn = Locale.call(%{conn | params: params}, [])

    case context.action do
      :next ->
        if context.pending do
          params = Map.put(params, "batch_end_id", positive_id(params["batch_end_id"]))
          reveal(conn, actor.id, params, context, 10)
        else
          Response.unlock(conn, 204)
        end

      :seen ->
        id = positive_id(context.id)
        token = params["claim_token"]

        status =
          cond do
            is_nil(id) or is_nil(token) or String.trim(token) == "" -> 400
            Deck.acknowledge(context.repo, actor.id, id, token, context) -> 204
            true -> 409
          end

        Response.unlock(conn, status)

      :dismiss ->
        if id = positive_id(params["batch_end_id"]) do
          :ok = Deck.dismiss_through(context.repo, actor.id, id, context)
          Response.unlock(conn, 204)
        else
          Response.unlock(conn, 400)
        end
    end
  rescue
    _ -> Response.terminal(conn)
  end

  defp reveal(conn, _, _, _, 0), do: Response.unlock(conn, 204)

  defp reveal(conn, id, params, context, attempts) do
    case Deck.claim(context.repo, id, params, context) do
      :busy ->
        Response.unlock(conn, 409, %{retry_after: 2})

      nil ->
        Response.unlock(conn, 204)

      claim ->
        case UnlockCard.call(context.repo, claim.event, context.state, context) do
          nil ->
            true =
              Deck.acknowledge(context.repo, id, claim.event.id, claim.event.claim_token, context)

            reveal(conn, id, params, context, attempts - 1)

          card ->
            html =
              Map.get(context, :render, &AchievementUnlockReveal.render/3).(
                card,
                claim.remaining,
                context.locale
              )

            Response.unlock(conn, 200, %{
              id: claim.event.id,
              token: claim.event.claim_token,
              batch_end_id: claim.batch_end_id,
              remaining: claim.remaining,
              html: html
            })
        end
    end
  end

  def positive_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  def positive_id(id) when is_binary(id),
    do: if(id =~ ~r/\A[1-9]\d{0,18}\z/, do: positive_id(String.to_integer(id)), else: nil)

  def positive_id(_), do: nil

  defp handoff(conn, opts) do
    upstream =
      Keyword.get_lazy(opts, :upstream, fn ->
        Application.fetch_env!(:dawarich, :rails_upstream)
      end)

    conn |> RailsProxy.call(upstream) |> halt()
  end
end
