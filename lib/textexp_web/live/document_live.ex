defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  on_mount {TextexpWeb.LiveUserAuth, :live_user_optional}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <script defer phx-track-static type="text/javascript" src={~p"/assets/js/blocknote.js"}>
      </script>
      <%!-- React gère ce nœud : LiveView ne doit pas y toucher --%>
      <div id="root" phx-update="ignore"></div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
