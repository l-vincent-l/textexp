// Hook of a search field whose results are listed in the element of its
// `aria-controls` (options: `role="option"`, each holding a link). The focus
// stays in the field: ↑ and ↓ move through the results, Enter opens the
// selected one. The first result is selected whenever they change. The field
// is emptied on the server's `search:clear` event.
//
// The selection is `aria-selected` on the option and `aria-activedescendant`
// on the field. LiveView removes these attributes when it patches the
// elements: they are put back.
export const SearchNav = {
  mounted() {
    this.list = document.getElementById(this.el.getAttribute("aria-controls"))
    this.active = 0
    this.ids = ""

    this.observer = new MutationObserver(() => this.highlight())
    this.observer.observe(this.list, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["aria-selected"],
    })

    this.el.addEventListener("keydown", event => {
      const options = this.options()
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        const step = event.key === "ArrowDown" ? 1 : -1
        this.active = Math.min(Math.max(this.active + step, 0), options.length - 1)
        this.highlight({scroll: true})
      } else if (event.key === "Enter" && options[this.active]) {
        event.preventDefault()
        options[this.active].querySelector("a")?.click()
      }
    })

    // Sent when a tag is picked: LiveView does not empty a focused field
    this.handleEvent("search:clear", () => {
      this.el.value = ""
    })

    this.highlight()
  },

  updated() {
    this.highlight()
  },

  destroyed() {
    this.observer.disconnect()
  },

  options() {
    return [...this.list.querySelectorAll("[role=option]")]
  },

  highlight({scroll = false} = {}) {
    const options = this.options()
    const ids = options.map(option => option.id).join(" ")
    if (ids !== this.ids) {
      this.ids = ids
      this.active = 0
    }

    options.forEach((option, i) => {
      const selected = String(i === this.active)
      // Only when it changes: the observer sees the attribute's changes
      if (option.getAttribute("aria-selected") !== selected) {
        option.setAttribute("aria-selected", selected)
      }
    })

    const current = options[this.active]
    if (current) {
      this.el.setAttribute("aria-activedescendant", current.id)
      if (scroll) current.scrollIntoView({block: "nearest"})
    } else {
      this.el.removeAttribute("aria-activedescendant")
    }
  },
}
