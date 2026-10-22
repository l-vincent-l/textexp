defmodule Textexp.Document.Document do
  @moduledoc """
  A collaborative document.

  Its Yjs content is stored in `snapshot`: the full state, rewritten at most
  every 10 s while it is being edited (see `Textexp.Document.YPersistence`).
  `excerpt` holds the first lines of its body, saved along with the snapshot to
  preview the document without decoding it.
  """
  use Ash.Resource,
    otp_app: :textexp,
    domain: Textexp.Document,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Largest Yjs state an import accepts.
  @max_import_bytes 5_000_000

  sqlite do
    table "documents"
    repo Textexp.SqliteRepo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title]
      change relate_actor(:owner)
    end

    create :import do
      description """
      Creates a document from the full Yjs state of its content, e.g. a file
      converted by BlockNote in the browser. The state is checked by applying
      it, and its excerpt saved along.
      """

      accept [:title]
      argument :snapshot, :binary, allow_nil?: false
      change relate_actor(:owner)

      change fn changeset, _context ->
        snapshot = Ash.Changeset.get_argument(changeset, :snapshot)
        doc = Yex.Doc.new()

        cond do
          not is_binary(snapshot) ->
            changeset

          byte_size(snapshot) > @max_import_bytes ->
            Ash.Changeset.add_error(changeset,
              field: :snapshot,
              message: "contenu trop volumineux"
            )

          Yex.apply_update(doc, snapshot) == :ok ->
            changeset
            |> Ash.Changeset.force_change_attribute(:snapshot, snapshot)
            |> Ash.Changeset.force_change_attribute(:excerpt, Textexp.Document.Body.excerpt(doc))

          true ->
            Ash.Changeset.add_error(changeset, field: :snapshot, message: "contenu illisible")
        end
      end
    end

    read :mine do
      filter expr(owner_id == ^actor(:id))
    end

    update :rename do
      accept [:title]
    end

    update :save_snapshot do
      description "Replaces the snapshot with the full Yjs state of the document, and its excerpt."
      require_atomic? false
      accept [:snapshot, :excerpt]

      # A document saved without title, but with text, gets a dated one. Without
      # text, it stays untitled so that it is deleted when left (see
      # YPersistence.unbind).
      change fn changeset, _context ->
        title = Ash.Changeset.get_attribute(changeset, :title)
        excerpt = Ash.Changeset.get_attribute(changeset, :excerpt)

        if (title == nil or String.trim(title) == "") and excerpt != nil do
          Ash.Changeset.force_change_attribute(
            changeset,
            :title,
            "Notes du #{Date.utc_today() |> Calendar.strftime("%d-%m-%Y")}"
          )
        else
          changeset
        end
      end
    end

    update :set_members do
      description "Replaces the members of the document: a list of `%{id: user_id, role: role}`."
      require_atomic? false
      argument :members, {:array, :map}
      # The owner, allowed to set the members (see the policies), looks up and
      # relates users they could not read otherwise.
      change manage_relationship(:members,
               type: :append_and_remove,
               join_keys: [:role],
               authorize?: false
             )
    end
  end

  # The owner can do anything, editors can read and write, viewers can only
  # read. YPersistence saves without actor, access being checked when joining
  # the document's channel (see TextexpWeb.YDocRoomChannel).
  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(memberships, user_id == ^actor(:id)))
    end

    policy action([:rename, :save_snapshot]) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and role == :editor))
    end

    policy action([:destroy, :set_members]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :snapshot, :binary

    attribute :excerpt, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, Textexp.Accounts.User do
      public? true
    end

    has_many :memberships, Textexp.Document.Membership

    many_to_many :members, Textexp.Accounts.User do
      through Textexp.Document.Membership
      join_relationship :memberships
      source_attribute_on_join_resource :document_id
      destination_attribute_on_join_resource :user_id
    end
  end

  calculations do
    # The snapshot is rewritten on each save, so this is `updated_at` (which
    # also changes on rename).
    calculate :last_update, :utc_datetime_usec, expr(updated_at)

    calculate :markdown, :string, {Textexp.Document.BodyContent, format: :markdown} do
      description "The body as Markdown, from the saved snapshot."
      public? true
    end

    calculate :text, :string, {Textexp.Document.BodyContent, format: :text} do
      description "The text of the body, one line per block, from the saved snapshot."
      public? true
    end
  end
end
