defmodule YPhoenix.Channel do
  @moduledoc """
  Functions for a Phoenix channel that syncs a Yjs document with a
  `YPhoenix.DocServer`. The app's channel handles authorization and delegates
  the rest:

      def join("y_doc_room:" <> doc_name = topic, _payload, socket) do
        if authorized?(socket, doc_name) do
          YPhoenix.Channel.join(socket, topic, doc_name, @doc_server_opts)
        else
          {:error, %{reason: "unauthorized"}}
        end
      end

      def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)
      def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)

  Options: those of `YPhoenix.DocServer`, plus

    * `:supervisor` - `DynamicSupervisor` under which DocServers are started;
    * `:registry_scope` - `:syn` scope in which DocServers are registered by
      document name, so there is only one per document in the cluster.
  """

  require Logger

  import Phoenix.Channel, only: [push: 3]
  import Phoenix.Socket, only: [assign: 2]

  alias YPhoenix.DocServer

  def join(socket, topic, doc_name, opts) do
    uid = "#{node()}_#{System.unique_integer()}"

    Keyword.fetch!(opts, :presence).track_user(topic, uid, %{})

    case start_doc_server(topic, doc_name, opts) do
      {:ok, docpid} ->
        Process.monitor(docpid)
        {:ok, assign(socket, doc_name: doc_name, doc_pid: docpid, doc_server_opts: opts)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_in(event, {:binary, chunk}, socket) when event in ["yjs_sync", "yjs"] do
    server = socket.assigns.doc_pid

    DocServer.process_message_v1(server, chunk, self())
    |> handle_process_message_result(server)

    {:noreply, socket}
  end

  defp handle_process_message_result(result, server) do
    case result do
      {:ok, replies} ->
        Enum.each(replies, fn reply ->
          send(self(), {:yjs, reply, server})
        end)

        :ok

      error ->
        error
    end
  end

  def handle_info({:yjs, message, _proc}, socket) do
    push(socket, "yjs", {:binary, message})
    {:noreply, socket}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        %{assigns: %{doc_pid: pid, doc_name: doc_name, doc_server_opts: opts}} = socket
      ) do
    # Only handle :DOWN for the current doc_pid
    case start_doc_server(socket.topic, doc_name, opts) do
      {:ok, docpid} ->
        Process.monitor(docpid)
        push(socket, "yjs_resync", %{})
        {:noreply, assign(socket, doc_pid: docpid)}

      {:error, reason} ->
        push(socket, "yjs_server_down", %{})
        {:stop, {:error, "failed to restart shared doc: #{inspect(reason)}"}, socket}
    end
  end

  # Catch-all for unrelated :DOWNs (do nothing)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket), do: {:noreply, socket}

  defp start_doc_server(topic, doc_name, opts) do
    scope = Keyword.fetch!(opts, :registry_scope)

    case :syn.lookup(scope, doc_name) do
      {pid, _metadata} ->
        {:ok, pid}

      :undefined ->
        doc_server_opts =
          [topic: topic, doc_name: doc_name] ++
            Keyword.drop(opts, [:supervisor, :registry_scope])

        DynamicSupervisor.start_child(Keyword.fetch!(opts, :supervisor), %{
          id: DocServer,
          start:
            {DocServer, :start_link, [doc_server_opts, [name: {:via, :syn, {scope, doc_name}}]]},
          # the channel restarts the DocServer itself when it stops (see :DOWN)
          restart: :temporary
        })
    end
    |> case do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("""
        Failed to start shareddoc.
        Room: #{inspect(doc_name)}
        Reason: #{inspect(reason)}
        """)

        {:error, %{reason: "failed to start shareddoc"}}
    end
  end
end
