defmodule DawarichWeb.NativeTripDocument do
  @moduledoc false
  use DawarichWeb, :html

  def render(assigns) do
    assigns =
      assign(assigns,
        request_path:
          assigns[:request_path] || "/trips/#{assigns.page && assigns.page.presentation.id}",
        query_params: assigns[:query_params] || %{},
        self_hosted: assigns[:self_hosted] != false
      )

    assigns = assign(assigns, :inner_content, page(assigns))

    ~H"""
    <DawarichWeb.Layouts.app {assigns} />
    """
  end

  defp page(assigns) do
    ~H"""
    <div
      :if={@page}
      id="trip-shell"
      data-native-map-root
      class="contents [&>#video-studio-owner]:contents"
    >
      <div class="container mx-auto px-4 my-5">
        <div class="flex flex-col lg:flex-row gap-6 lg:h-[calc(100dvh-9.75rem)]">
          <div class="w-full min-w-0 lg:w-3/5 h-[50vh] lg:h-full shrink-0">
            <DawarichWeb.NativeTripMapPanel.panel
              config={@page.config}
              locale={@locale}
              state={@page.presentation.map_state}
              has_path={@page.presentation.has_path}
              future={@page.presentation.future_start}
            />
          </div>
          <div class="w-full min-w-0 lg:w-2/5 lg:h-full lg:overflow-y-auto">
            <DawarichWeb.NativeTripActions.actions page={@page.presentation} locale={@locale} />
            <DawarichWeb.NativeTripToolbar.toolbar
              page={@page}
              expanded={@expanded_days}
              locale={@locale}
            />
            <DawarichWeb.NativeTripContent.content
              page={@page.presentation}
              locale={@locale}
              selected_day={@selected_day}
              note_editor={@note_editor}
              expanded_days={@expanded_days}
              plan_enabled={@page.presentation.plan_on_map}
            />
          </div>
        </div>
      </div>
      <DawarichWeb.NativeTripPosterStudio.render
        themes={@page.studio.themes}
        posters={@posters}
        print_order_url={@page.studio.print_order_url}
        locale={@locale}
        fixed_range_label={@page.range_label}
      />
      <.live_component
        module={DawarichWeb.VideoStudioLiveComponent}
        native={true}
        id="video-studio-owner"
        scope={@current_scope}
        locale={@locale}
        base_url={assigns[:base_url] || ""}
        themes={@page.studio.themes}
        fixed_range_label={@page.range_label}
      />
    </div>
    <DawarichWeb.NativeTripConfirmation.dialog confirmation={@trip_confirmation} locale={@locale} />
    <p :if={@map_error} role="alert">{to_string(@map_error)}</p>
    """
  end
end
