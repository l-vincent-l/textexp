defmodule TextexpWeb.YDocRoomChannel do
  use TextexpWeb, :channel

  @doc_server_opts [
    endpoint: TextexpWeb.Endpoint,
    persistence: Textexp.Document.YPersistence,
    presence: TextexpWeb.Presence,
    supervisor: TextexpWeb.DocServerSupervisor,
    registry_scope: :doc_servers
  ]

  @doc "Options passed to `YPhoenix.Channel` and `YPhoenix.DocServer`."
  def doc_server_opts, do: @doc_server_opts

  @impl true
  def join("y_doc_room:" <> doc_name = topic, _payload, socket) do
    if authorized?(socket, doc_name) do
      YPhoenix.Channel.join(socket, topic, doc_name, @doc_server_opts)
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)

  @impl true
  def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)

  # Any signed-in user can join any existing document.
  defp authorized?(socket, document_id) do
    socket.assigns[:current_user] != nil and
      match?({:ok, _}, Textexp.Document.get_document(document_id))
  end
end
