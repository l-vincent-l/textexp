defmodule TextexpWeb.DocumentLive do
  use TextexpWeb, :live_view

  alias Textexp.Document
  alias Textexp.Document.YPersistence
  alias TextexpWeb.Presence

  on_mount {TextexpWeb.LiveUserAuth, :live_user_required}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} full_width>
      <%= if @document do %>
        <link phx-track-static rel="stylesheet" href={~p"/assets/js/blocknote.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/blocknote.js"}>
        </script>
      <% end %>
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

          <%= if @document do %>
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
                <div class="mt-1 flex flex-wrap items-center justify-between gap-2">
                  <p id="last-update" class="text-sm text-[#9b9b9b]">
                    Dernière mise à jour : {Calendar.strftime(@last_update, "%d/%m/%Y %H:%M:%S")} UTC
                  </p>
                  <%!-- Personnes ayant ce document ouvert --%>
                  <ul id="viewers" class="flex -space-x-2" phx-update="stream">
                    <li
                      :for={{id, viewer} <- @streams.viewers}
                      id={id}
                      title={viewer.email}
                      class={[
                        "flex size-8 items-center justify-center rounded-full text-xs font-semibold uppercase",
                        "ring-2 ring-white transition-transform duration-150 hover:z-10 hover:-translate-y-0.5",
                        if(viewer.id == @current_user.id,
                          do: "bg-[#3f3f3f] text-white",
                          else: "bg-[#ececec] text-[#3f3f3f]"
                        )
                      ]}
                    >
                      {String.first(to_string(viewer.email))}
                    </li>
                  </ul>
                </div>
                <div class="divider"></div>
              </div>
              <%!-- React gère ce nœud : LiveView ne doit pas y toucher --%>
              <div
                id="root"
                class="flex-1 w-full"
                phx-update="ignore"
                data-document-id={@document.id}
                data-user-name={@current_user.email}
              >
              </div>
            </div>
          <% else %>
            <div id="no-document" class="flex flex-1 flex-col items-center justify-center gap-4 p-8">
              <.icon name="hero-document-text" class="size-12 opacity-30" />
              <p class="text-base-content/60">Choisissez un document ou créez-en un.</p>
              <button id="new-document-empty" class="btn btn-primary" phx-click="new_document">
                <.icon name="hero-plus" class="size-4" /> Nouveau document
              </button>
            </div>
          <% end %>
        </div>

        <div class="drawer-side z-20">
          <label for="sidebar-drawer" aria-label="Fermer le menu" class="drawer-overlay"></label>
          <div class="flex min-h-full w-64 flex-col bg-base-200 p-4">
            <button
              id="new-document"
              class="btn btn-ghost btn-sm mb-2 justify-start"
              phx-click="new_document"
            >
              <.icon name="hero-plus" class="size-4" /> Nouveau document
            </button>
            <%!-- Liens en href (rechargement complet) : l'éditeur BlockNote est
                 initialisé une seule fois au chargement de la page. --%>
            <ul id="documents" class="menu w-full p-0" phx-update="stream">
              <li id="documents-empty" class="hidden only:block px-3 py-2 text-sm opacity-60">
                Aucun document
              </li>
              <li :for={{id, document} <- @streams.documents} id={id}>
                <.link
                  href={~p"/documents/#{document.id}"}
                  class={[@document && @document.id == document.id && "menu-active"]}
                >
                  <.icon name="hero-document-text" class="size-4" />
                  <span class="truncate">{document.title || "Sans titre"}</span>
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    documents = Document.list_documents!(query: [sort: [last_update: :desc]])

    {:ok,
     socket
     |> assign(document: nil, title_form: nil)
     |> stream(:viewers, [])
     |> stream(:documents, documents)}
  end

  def handle_params(%{"id" => id}, _uri, socket) do
    case Document.get_document(id, load: [:last_update]) do
      {:ok, document} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))

          user = socket.assigns.current_user
          Presence.subscribe(viewers_topic(document.id))

          Presence.track_user(viewers_topic(document.id), user.id, %{
            id: user.id,
            email: user.email
          })
        end

        {:noreply,
         assign(socket,
           document: document,
           page_title: document.title || "Sans titre",
           last_update: document.last_update,
           title_form: to_form(%{"title" => document.title})
         )}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Document introuvable")
         |> push_navigate(to: ~p"/documents")}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def handle_info({:document_updated, _document_id, at}, socket) do
    {:noreply, assign(socket, last_update: at)}
  end

  def handle_info({Presence, {event, _user}}, socket) when event in [:join, :leave] do
    {:noreply, stream(socket, :viewers, viewers(socket.assigns.document.id), reset: true)}
  end

  defp viewers_topic(document_id), do: "viewers:#{document_id}"

  # Un utilisateur avec plusieurs onglets ouverts n'apparaît qu'une fois.
  defp viewers(document_id) do
    document_id
    |> viewers_topic()
    |> Presence.list_users()
    |> Enum.map(fn %{metas: [meta | _]} -> meta end)
    |> Enum.sort_by(& &1.email)
  end

  def handle_event("new_document", _params, socket) do
    document = Document.create_document!(%{}, actor: socket.assigns.current_user)
    {:noreply, redirect(socket, to: ~p"/documents/#{document.id}")}
  end

  def handle_event("update_title", %{"title" => title}, socket) do
    document = Document.rename_document!(socket.assigns.document, title)

    {:noreply,
     socket
     |> assign(
       document: document,
       page_title: document.title || "Sans titre",
       title_form: to_form(%{"title" => document.title})
     )
     |> stream_insert(:documents, document)}
  end
end
