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

  # Users can join the documents they can read (owner and members), and edit
  # those they can save (owner and editors); viewers join read-only. The rights
  # are those of the policies of Textexp.Document.Document, checked once on
  # join: a role removed meanwhile only applies on the next join.
  @impl true
  def join("y_doc_room:" <> doc_name = topic, _payload, socket) do
    with %{} = user <- socket.assigns[:current_user],
         {:ok, document} <- Textexp.Document.get_document(doc_name, actor: user) do
      read_only? = not Ash.can?({document, :save_snapshot}, user)
      YPhoenix.Channel.join(socket, topic, doc_name, [read_only: read_only?] ++ @doc_server_opts)
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)

  @impl true
  def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)
end
