// Hook of the documents page's file input: each chosen file (Markdown, HTML or
// plain text) is converted to a document by BlockNote, in the browser, and its
// Yjs state sent to the server, which creates the document. One imported file
// is opened. The BlockNote bundle is only loaded on the first import.
const MAX_BYTES = 2_000_000

export const DocumentImport = {
  mounted() {
    this.el.addEventListener("change", () => this.importFiles([...this.el.files]))
  },

  async importFiles(files) {
    // so that choosing the same file again triggers a change
    this.el.value = ""
    if (files.length === 0) return

    const card = this.el.closest("[data-import]")
    this.js().setAttribute(card, "aria-busy", "true")
    const ids = []

    try {
      const {toYjsState} = await import("./blocknote/convert")

      for (const file of files) {
        const reply = await this.importFile(file, toYjsState)
        if (reply.id) ids.push(reply.id)
      }
    } finally {
      this.js().removeAttribute(card, "aria-busy")
    }

    if (files.length === 1 && ids.length === 1) this.js().navigate(`/documents/${ids[0]}`)
  },

  async importFile(file, toYjsState) {
    if (file.size > MAX_BYTES) {
      return this.push("import_failed", {name: file.name, reason: "too_large"})
    }

    try {
      const format = /\.html?$/i.test(file.name) ? "html" : "markdown"
      const state = await toYjsState(await file.text(), format)
      return await this.push("import_document", {name: file.name, state: toBase64(state)})
    } catch (error) {
      console.error(error)
      return this.push("import_failed", {name: file.name, reason: "unreadable"})
    }
  },

  push(event, payload) {
    return new Promise(resolve => this.pushEvent(event, payload, reply => resolve(reply || {})))
  },
}

// btoa takes a string of bytes, built in chunks: spreading a large array at
// once would overflow the call stack.
function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
