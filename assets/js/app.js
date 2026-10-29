import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

Hooks.CopyToClipboard = {
  mounted() {
    this.originalLabel = this.el.getAttribute("aria-label")
    this.originalTitle = this.el.getAttribute("title")
    this.status = this.el.querySelector("[data-copy-status]")

    this.copy = async () => {
      try {
        await navigator.clipboard.writeText(this.el.dataset.copyText)
        this.el.dataset.copyState = "copied"
        this.el.setAttribute("aria-label", `Copied ${this.el.dataset.copyText}`)
        this.el.setAttribute("title", "Copied tag")
        this.status.textContent = "Copied tag"

        window.clearTimeout(this.resetTimer)
        this.resetTimer = window.setTimeout(() => this.reset(), 1500)
      } catch (_error) {
        this.el.dataset.copyState = "error"
        this.el.setAttribute("aria-label", `Couldn't copy ${this.el.dataset.copyText}`)
        this.el.setAttribute("title", "Couldn't copy tag")
        this.status.textContent = "Couldn't copy tag"

        window.clearTimeout(this.resetTimer)
        this.resetTimer = window.setTimeout(() => this.reset(), 1500)
      }
    }

    this.el.addEventListener("click", this.copy)
  },

  destroyed() {
    this.el.removeEventListener("click", this.copy)
    window.clearTimeout(this.resetTimer)
  },

  reset() {
    delete this.el.dataset.copyState
    this.el.setAttribute("aria-label", this.originalLabel)
    this.el.setAttribute("title", this.originalTitle)
    this.status.textContent = ""
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()
window.liveSocket = liveSocket
