defmodule Textexp.Document.Document do
  @moduledoc """
  A collaborative document.

  Its Yjs content is stored in `snapshot`: the full state, rewritten at most
  every 10 s while it is being edited (see `Textexp.Document.YPersistence`).
  `excerpt` holds the first lines of its body, saved along with the snapshot to
  preview the document without decoding it.
  """
  use Ash.Resource, otp_app: :textexp, domain: Textexp.Document, data_layer: AshSqlite.DataLayer

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
