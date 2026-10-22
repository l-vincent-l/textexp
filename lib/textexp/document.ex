defmodule Textexp.Document do
  use Ash.Domain,
    otp_app: :textexp,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Textexp.Document.Document do
      define :create_document, action: :create
      define :import_document, action: :import, args: [:title, :snapshot]
      define :get_document, action: :read, get_by: [:id]
      define :list_documents, action: :read
      define :list_my_documents, action: :mine
      define :rename_document, action: :rename, args: [:title]
      define :save_snapshot, action: :save_snapshot, args: [:snapshot]
      define :destroy_document, action: :destroy
      define :set_document_members, action: :set_members, args: [:members]
      define_calculation :document_markdown, calculation: :markdown, args: [:_record]
    end

    resource Textexp.Document.Membership do
      define :share_document, action: :share, args: [:document_id, :email, :role]
      define :list_document_members, action: :for_document, args: [:document_id]
      define :remove_document_member, action: :destroy
    end
  end
end
