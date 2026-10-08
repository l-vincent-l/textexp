defmodule Textexp.YEcto do
  defmacro __using__(opts) do
    repo = opts[:repo]
    schema = opts[:schema]

    quote do
      require Ash.Query

      @repo unquote(repo)
      @schema unquote(schema)

      @flush_size 400

      def get_y_doc(doc_name) do
        ydoc = Yex.Doc.new()

        updates = get_updates(doc_name)

        Yex.Doc.transaction(ydoc, fn ->
          Enum.each(updates, fn update ->
            Yex.apply_update(ydoc, update.value)
          end)
        end)

        if length(updates) > @flush_size do
          {:ok, u} = Yex.encode_state_as_update(ydoc)
          {:ok, sv} = Yex.encode_state_vector(ydoc)
          clock = List.last(updates, nil).inserted_at
          flush_document(doc_name, u, sv, clock)
        end

        ydoc
      end

      def insert_update(doc_name, value) do
        @schema
        |> Ash.Changeset.for_create(:create, %{doc_name: doc_name, value: value, version: :v1})
        |> Ash.create!()
      end

      def get_state_vector(doc_name) do
        @schema
        |> Ash.Query.for_read(:get_state_vector, %{doc_name: doc_name})
        |> Ash.read!()
      end

      def get_diff(doc_name, sv) do
        doc = get_y_doc(doc_name)
        Yex.encode_state_as_update(doc, sv)
      end

      def clear_document(doc_name) do
        @schema
        |> Ash.Query.do_filter(doc_name: doc_name)
        |> Ash.bulk_destroy!(:destroy, %{})
      end

      defp put_state_vector(doc_name, state_vector) do
        case get_state_vector(doc_name) do
          nil -> %@schema{doc_name: doc_name, version: :v1_sv}
          state_vector -> state_vector
        end
        |> Ash.Changeset.for_create(:create, %{value: state_vector})
        |> Ash.create!()
      end

      defp get_updates(doc_name) do
        @schema
        |> Ash.Query.for_read(:get_updates, %{doc_name: doc_name})
        |> Ash.read!()
      end

      defp flush_document(doc_name, updates, sv, clock) do
        @schema
        |> Ash.Changeset.for_create(:create, %@schema{
          doc_name: doc_name,
          value: updates,
          version: :v1
        })
        |> Ash.create!()

        put_state_vector(doc_name, sv)
        clear_updates_to(doc_name, clock)
      end

      defp clear_updates_to(doc_name, to) do
        @schema
        |> Ash.Query.do_filter(doc_name: doc_name, inserted_at: [less_than: to])
        |> Ash.bulk_destroy!(:destroy, %{})
      end
    end
  end
end
