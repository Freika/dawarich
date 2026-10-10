defmodule DawarichWeb.PublicHomeLive do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Auth.RegistrationSetting

  @layout ~w(locale suggested_locale self_hosted request_path query_params rails_csrf_token base_url)a

  def registration(false), do: {:ok, true}
  def registration(true), do: RegistrationSetting.fetch()

  def mount(_params, session, socket) do
    rendered = session["rails_user_id"]

    connected =
      if connected?(socket),
        do: (get_connect_info(socket, :session) || %{})["rails_user_id"],
        else: rendered

    with true <- is_nil(rendered) and is_nil(connected),
         {:ok, enabled} <- registration(session["self_hosted"] != false) do
      socket =
        socket
        |> assign(:current_user, nil)
        |> assign(:now, DateTime.utc_now())
        |> assign(:page_title, nil)
        |> assign(:flash_messages, [])
        |> assign(:registration_enabled, enabled)
        |> assign(for key <- @layout, do: {key, session[Atom.to_string(key)]})
        |> assign(
          :navbar,
          Dawarich.Navbar.load(nil, now: DateTime.utc_now(), self_hosted: session["self_hosted"])
        )
        |> rails_flash(session["flash_messages"] || [])
        |> attach_hook(:guest_identity, :handle_event, &guest_identity/3)
        |> DawarichWeb.NavbarHooks.attach(params: false)

      {:ok, socket, layout: {DawarichWeb.Layouts, :app}}
    else
      _ -> {:ok, redirect(socket, to: "/")}
    end
  end

  defp rails_flash(socket, messages) do
    if connected?(socket),
      do: socket,
      else:
        Enum.reduce(messages, socket, fn {type, message}, acc ->
          put_flash(acc, to_string(type), message)
        end)
  end

  defp guest_identity(_event, _params, socket) do
    user = socket.assigns.current_user
    if is_nil(user), do: {:cont, socket}, else: {:halt, redirect(socket, to: "/")}
  end

  def render(assigns) do
    ~H"""
    <div class="w-full mx-auto my-5">
      <div class="flex justify-between items-center mt-5 mb-5">
        <div class="hero h-fit bg-base-200 py-20">
          <div class="hero-content text-center">
            <div class="max-w-md">
              <h1 class="text-5xl font-bold">
                <a href="https://dawarich.app" class="link">{t(@locale, "home.index.dawarich", %{})}</a>
              </h1>
              <p class="py-6 text-3xl">
                {t(@locale, "home.index.the_only_location_history_tracker_you_ll_ever_need", %{})}
              </p>

              <%= if @registration_enabled do %>
                <a
                  href="/users/sign_up"
                  class="rounded-lg py-3 px-5 my-3 bg-blue-600 text-white block font-medium"
                >{t(@locale, "home.index.sign_up", %{})}</a>
                <div class="divider">{t(@locale, "home.index.or", %{})}</div>
              <% end %>
              <a
                href="/users/sign_in"
                class="rounded-lg py-3 px-5 bg-neutral text-neutral-content block font-medium"
              >{t(@locale, "home.index.sign_in", %{})}</a>
            </div>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-1 gap-4 m-auto justify-center md:grid-cols-2 xl:grid-cols-3">
        <div class="card w-full max-w-sm bg-base-100 justify-self-center shadow-xl">
          <div class="card-body">
            <h2 class="card-title mx-auto">
              {t(@locale, "home.index.location_history_visualisation", %{})}
            </h2>
            <p class="text-center">
              {t(
                @locale,
                "home.index.effortlessly_import_your_location_history_from_google_maps_timeline_and",
                %{}
              )}
            </p>
          </div>
        </div>

        <div class="card w-full max-w-sm bg-base-100 justify-self-center shadow-xl">
          <div class="card-body">
            <h2 class="card-title mx-auto">
              {t(@locale, "home.index.comprehensive_travel_statistics", %{})}
            </h2>
            <p class="text-center">
              {t(
                @locale,
                "home.index.gain_insights_into_your_travel_patterns_with_detailed_statistics_track",
                %{}
              )}
            </p>
          </div>
        </div>

        <div class="card w-full max-w-sm bg-base-100 justify-self-center shadow-xl md:col-span-2 xl:col-span-1">
          <div class="card-body">
            <h2 class="card-title mx-auto">
              {t(@locale, "home.index.self_hosted_and_private", %{})}
            </h2>
            <p class="text-center">
              {t(
                @locale,
                "home.index.maintain_complete_control_over_your_data_with_our_self_hosted",
                %{}
              )}
            </p>
          </div>
        </div>
      </div>

      <div class="text-center my-10">
        {t(@locale, "home.index.find_more_on", %{})} <a href="https://dawarich.app" class="link">{t(@locale, "home.index.the_website", %{})}</a>{t(
          @locale,
          "home.index.or_check_out_the",
          %{}
        )}
        <a href="https://github.com/Freika/dawarich" class="link">{t(
          @locale,
          "home.index.source_code",
          %{}
        )}</a> {t(@locale, "home.index.on_github", %{})}
      </div>
    </div>
    """
  end
end
