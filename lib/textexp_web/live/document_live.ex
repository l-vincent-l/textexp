defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
      <script defer phx-track-static type="text/javascript" src={~p"/assets/js/blocknote.js"}>
      </script>
      <div class="drawer lg:drawer-open min-h-[calc(100vh-4rem)]">
        <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

        <div class="drawer-content flex flex-col">
          <%!-- Bouton d'ouverture : visible uniquement sur petit écran --%>
          <div class="p-2 lg:hidden">
            <label
              id="sidebar-open"
              for="sidebar-drawer"
              aria-label="Ouvrir le menu"
              class="btn btn-square btn-ghost drawer-button"
            >
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>

          <%!-- Le titre partage le fond, la police et les marges de l'éditeur BlockNote (thème light) --%>
          <div class="flex flex-1 flex-col bg-white font-['Inter',sans-serif] text-[#3f3f3f]">
            <div class="document-header px-[54px] pt-12 pb-2">
              <.form
                for={@title_form}
                id="title-form"
                phx-change="update_title"
                phx-submit="update_title"
              >
                <input
                  id="document-title"
                  name="title"
                  value={@title_form[:title].value}
                  placeholder="Sans titre"
                  phx-debounce="300"
                  autocomplete="off"
                  class="w-full bg-transparent text-4xl font-bold leading-tight outline-none placeholder:text-[#cfcfcf]"
                />
              </.form>
              <div class="divider"></div>
            </div>
            <%!-- React gère ce nœud : LiveView ne doit pas y toucher --%>
            <div
              id="root"
              class="flex-1 w-full"
              phx-update="ignore"
              data-user-name={@current_user.email}
            >
            </div>
          </div>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label="Fermer le menu" class="drawer-overlay"></label>
          <ul id="sidebar-menu" class="menu bg-base-200 min-h-full w-64 p-4">
            <li>
              <a href="/">
                <.icon name="hero-home" class="size-4" /> Accueil
              </a>
            </li>
            <li>
              <a href="#">
                <.icon name="hero-cog-6-tooth" class="size-4" /> Paramètres
              </a>
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, title_form: to_form(%{"title" => "titre"}))}
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    # {:ok, doc} = save_title(socket.assigns.doc, title)
    # broadcast PubSub comme ci-dessus
    {:noreply, assign(socket, title_form: to_form(%{"title" => title}))}
  end
end
