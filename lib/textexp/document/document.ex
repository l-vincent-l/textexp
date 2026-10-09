defmodule Textexp.Document.Document do
  @moduledoc """
  Un document collaboratif.

  Son contenu Yjs est stocké en deux parties : `snapshot` contient l'état complet
  au dernier compactage, et les `writings` les updates incrémentales reçues depuis.
  """
  use Ash.Resource, otp_app: :textexp, domain: Textexp.Document, data_layer: AshSqlite.DataLayer

  require Ash.Query

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

    update :rename do
      accept [:title]
    end

    update :compact do
      description "Remplace le snapshot par l'état complet et supprime les writings qu'il intègre."
      require_atomic? false
      accept [:snapshot]

      argument :until, :utc_datetime_usec, allow_nil?: false

      change after_action(fn changeset, document, _context ->
               until = Ash.Changeset.get_argument(changeset, :until)

               Textexp.Document.Writing
               |> Ash.Query.filter(document_id == ^document.id and inserted_at <= ^until)
               |> Ash.bulk_destroy!(:destroy, %{}, strategy: [:atomic, :stream])

               {:ok, document}
             end)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :snapshot, :binary
    timestamps()
  end

  relationships do
    belongs_to :owner, Textexp.Accounts.User do
      public? true
    end

    has_many :writings, Textexp.Document.Writing
  end

  calculations do
    # Date du dernier writing ; une fois les writings compactés, celle du
    # compactage (ou du dernier renommage), portée par `updated_at`.
    # AshSqlite ne gère pas les aggregates, d'où la sous-requête en fragment ;
    # `||` y renvoie nil sur des dates, d'où le coalesce SQL.
    calculate :last_update,
              :utc_datetime_usec,
              expr(
                fragment(
                  "coalesce((SELECT max(inserted_at) FROM writings WHERE document_id = ?), ?)",
                  id,
                  updated_at
                )
              )
  end
end
