// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// JS hooks — the client half of the UI-layout / interop paradigm.
// Contract names come from the generated ./contracts (single-sourced in
// ZeroCoupled.Web.Contracts; `mix zc.gen.contracts --check` guards drift).
import {Hooks as HookNames, PushEvents, Streams} from "./contracts"

let Hooks = {}

// Focuses an input when it mounts (e.g. the checkout address form).
Hooks[HookNames.auto_focus] = {
  mounted() { this.el.focus() }
}

// Fades a cart row out just before it is removed. The server pushes the
// item-removed event via an Effects.Push effect; we animate the matching row.
Hooks[HookNames.remove_fade] = {
  mounted() {
    this.handleEvent(PushEvents.item_removed, ({id}) => {
      const row = document.getElementById(`${Streams.cart}-${id}`)
      if (row) { row.style.transition = "opacity .2s"; row.style.opacity = "0" }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}, hooks: Hooks})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

