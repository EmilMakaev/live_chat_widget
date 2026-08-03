import { Socket } from "phoenix"

// Entry point for the embeddable widget: <script src=".../widget.js" data-site-token="...">.
// Ships as its own small bundle (see config/config.exs :widget esbuild profile) so
// embedding it never pulls in Phoenix LiveView / the operator panel's JS.
;(function () {
  const scriptTag = document.currentScript || findOwnScriptTag()
  if (!scriptTag) return

  const siteToken = scriptTag.dataset.siteToken
  if (!siteToken) {
    console.error("[chat-widget] missing data-site-token on the embed <script> tag")
    return
  }

  const origin = new URL(scriptTag.src).origin
  const wsUrl = origin.replace(/^http/, "ws") + "/widget_socket"
  const storageKey = `lcw_visitor_token:${siteToken}`
  const visitorToken = getOrCreateVisitorToken(storageKey)

  const ui = buildUI()
  document.addEventListener("DOMContentLoaded", () => document.body.appendChild(ui.root))
  if (document.readyState !== "loading") document.body.appendChild(ui.root)

  const socket = new Socket(wsUrl)
  socket.connect()

  const channel = socket.channel(`widget:${siteToken}`, {
    visitor_token: visitorToken,
    user_agent: navigator.userAgent,
    referrer: document.referrer
  })

  channel
    .join()
    .receive("ok", (resp) => {
      localStorage.setItem(storageKey, resp.visitor_token)
      resp.messages.forEach(ui.appendMessage)
      ui.setStatus("online")
    })
    .receive("error", (resp) => {
      ui.setStatus("offline")
      console.error("[chat-widget] join failed", resp)
    })

  channel.on("message:new", ui.appendMessage)

  socket.onError(() => ui.setStatus("offline"))
  socket.onOpen(() => ui.setStatus("online"))

  ui.onSend((body) => {
    channel.push("message:new", { body }).receive("error", (resp) => {
      ui.showError(errorText(resp.reason))
    })
  })

  function errorText(reason) {
    switch (reason) {
      case "rate_limited":
        return "Слишком много сообщений подряд — подождите немного."
      case "too_long":
        return "Сообщение слишком длинное."
      default:
        return "Не удалось отправить сообщение."
    }
  }

  function findOwnScriptTag() {
    return Array.from(document.getElementsByTagName("script")).find((s) =>
      s.src && s.src.includes("widget.js")
    )
  }

  function getOrCreateVisitorToken(key) {
    let token = localStorage.getItem(key)
    if (!token) {
      token = "v_" + cryptoRandom()
      localStorage.setItem(key, token)
    }
    return token
  }

  function cryptoRandom() {
    if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID()
    return Math.random().toString(36).slice(2) + Date.now().toString(36)
  }

  function buildUI() {
    const root = document.createElement("div")
    root.style.all = "initial"
    const shadow = root.attachShadow({ mode: "open" })

    shadow.innerHTML = `
      <style>${css()}</style>
      <div class="lcw-launcher" part="launcher">💬</div>
      <div class="lcw-panel" hidden>
        <div class="lcw-header">
          <span>Чат с нами</span>
          <span class="lcw-status">●</span>
        </div>
        <div class="lcw-messages"></div>
        <div class="lcw-error" hidden></div>
        <form class="lcw-form">
          <input type="text" maxlength="4000" placeholder="Напишите сообщение…" autocomplete="off" />
          <button type="submit">Отправить</button>
        </form>
      </div>
    `

    const launcher = shadow.querySelector(".lcw-launcher")
    const panel = shadow.querySelector(".lcw-panel")
    const messages = shadow.querySelector(".lcw-messages")
    const errorBox = shadow.querySelector(".lcw-error")
    const form = shadow.querySelector(".lcw-form")
    const input = shadow.querySelector("input")
    const status = shadow.querySelector(".lcw-status")

    launcher.addEventListener("click", () => {
      panel.hidden = !panel.hidden
      if (!panel.hidden) input.focus()
    })

    let onSendCallback = () => {}
    form.addEventListener("submit", (e) => {
      e.preventDefault()
      const body = input.value.trim()
      if (!body) return
      onSendCallback(body)
      input.value = ""
    })

    return {
      root,
      onSend(cb) {
        onSendCallback = cb
      },
      appendMessage(message) {
        errorBox.hidden = true
        const el = document.createElement("div")
        const mine = message.sender_type === "visitor"
        el.className = `lcw-msg ${mine ? "lcw-msg--me" : "lcw-msg--them"}`
        el.textContent = message.body
        messages.appendChild(el)
        messages.scrollTop = messages.scrollHeight
      },
      showError(text) {
        errorBox.hidden = false
        errorBox.textContent = text
      },
      setStatus(state) {
        status.className = `lcw-status lcw-status--${state}`
      }
    }
  }

  function css() {
    return `
      :host, * { box-sizing: border-box; font-family: -apple-system, system-ui, sans-serif; }
      .lcw-launcher {
        position: fixed; bottom: 20px; right: 20px; width: 56px; height: 56px;
        border-radius: 50%; background: #2563eb; color: #fff; display: flex;
        align-items: center; justify-content: center; font-size: 24px; cursor: pointer;
        box-shadow: 0 4px 14px rgba(0,0,0,.25); z-index: 2147483000;
      }
      .lcw-panel {
        position: fixed; bottom: 88px; right: 20px; width: 320px; max-width: calc(100vw - 40px);
        height: 440px; max-height: calc(100vh - 120px); background: #fff; border-radius: 12px;
        box-shadow: 0 8px 30px rgba(0,0,0,.2); display: flex; flex-direction: column;
        overflow: hidden; z-index: 2147483000;
      }
      .lcw-panel[hidden] { display: none; }
      .lcw-header {
        background: #2563eb; color: #fff; padding: 12px 16px; font-weight: 600;
        display: flex; justify-content: space-between; align-items: center;
      }
      .lcw-status--online { color: #4ade80; }
      .lcw-status--offline { color: #f87171; }
      .lcw-messages { flex: 1; overflow-y: auto; padding: 12px; background: #f8fafc; }
      .lcw-msg { max-width: 80%; margin-bottom: 8px; padding: 8px 12px; border-radius: 10px; font-size: 14px; line-height: 1.35; word-wrap: break-word; }
      .lcw-msg--them { background: #e2e8f0; margin-right: auto; }
      .lcw-msg--me { background: #2563eb; color: #fff; margin-left: auto; }
      .lcw-error { background: #fef2f2; color: #b91c1c; font-size: 12px; padding: 6px 12px; }
      .lcw-form { display: flex; border-top: 1px solid #e2e8f0; }
      .lcw-form input { flex: 1; border: none; padding: 10px 12px; font-size: 14px; outline: none; }
      .lcw-form button { border: none; background: #2563eb; color: #fff; padding: 0 16px; cursor: pointer; font-size: 14px; }
    `
  }
})()
