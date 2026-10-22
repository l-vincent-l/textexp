// Converts a file's content to the Yjs state of a document, as the editor
// (blocknote.tsx) stores it: BlockNote parses it into blocks, written into the
// editor's XML fragment. Loaded on demand by the DocumentImport hook
// (document_import.js).
import { BlockNoteEditor } from "@blocknote/core";
import { blocksToYDoc } from "@blocknote/core/yjs";
import * as Y from "yjs";

// The fragment the editor syncs (see withCollaboration in blocknote.tsx, and
// Textexp.Document.Body on the server).
const FRAGMENT = "document-store";

/** The Yjs state of a document holding `content`, Markdown (or plain text) or HTML. */
export async function toYjsState(
  content: string,
  format: "markdown" | "html",
): Promise<Uint8Array> {
  // Not mounted: only its schema and parsers are used.
  const editor = BlockNoteEditor.create();
  const blocks =
    format === "html"
      ? await editor.tryParseHTMLToBlocks(content)
      : await editor.tryParseMarkdownToBlocks(content);

  const ydoc = blocksToYDoc(editor, blocks, FRAGMENT);
  const state = Y.encodeStateAsUpdate(ydoc);
  ydoc.destroy();
  return state;
}
