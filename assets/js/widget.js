import { Socket } from "phoenix"

// Entry point for the embeddable widget: <script src=".../widget.js" data-site-token="...">.
// Ships as its own small bundle (see config/config.exs :widget esbuild profile) so
// embedding it never pulls in Phoenix LiveView / the operator panel's JS.
;(function () {
  const ICONS = {
    chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/></svg>',
    headset:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 18v-6a9 9 0 0 1 18 0v6"/><path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z"/></svg>',
    smiley:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><line x1="9" y1="9" x2="9.01" y2="9"/><line x1="15" y1="9" x2="15.01" y2="9"/></svg>',
    bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>',
    question:
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 2-2.5 3.5"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>'
  }

  const SIZES = {
    compact: { launcher: 48, iconScale: 0.5, panelW: 280, panelH: 380 },
    default: { launcher: 56, iconScale: 0.5, panelW: 320, panelH: 440 },
    large: { launcher: 64, iconScale: 0.5, panelW: 360, panelH: 520 }
  }

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
      if (resp.widget) ui.applyConfig(resp.widget)
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
      <div class="lcw-launcher" part="launcher">${ICONS.chat}</div>
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
      applyConfig(config) {
        if (config.color) root.style.setProperty("--lcw-color", config.color)

        if (config.icon && ICONS[config.icon]) {
          launcher.innerHTML = ICONS[config.icon]
        }

        const size = SIZES[config.size] || SIZES.default
        launcher.style.width = size.launcher + "px"
        launcher.style.height = size.launcher + "px"
        launcher.style.setProperty("--lcw-icon-size", Math.round(size.launcher * size.iconScale) + "px")
        panel.style.width = size.panelW + "px"
        panel.style.height = size.panelH + "px"
      },
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
        border-radius: 50%; background: var(--lcw-color, #2563eb); color: #fff; display: flex;
        align-items: center; justify-content: center; font-size: 24px; cursor: pointer;
        box-shadow: 0 4px 14px rgba(0,0,0,.25); z-index: 2147483000;
      }
      .lcw-launcher svg { width: var(--lcw-icon-size, 28px); height: var(--lcw-icon-size, 28px); }
      .lcw-panel {
        position: fixed; bottom: 88px; right: 20px; width: 320px; max-width: calc(100vw - 40px);
        height: 440px; max-height: calc(100vh - 120px); background: #fff; border-radius: 12px;
        box-shadow: 0 8px 30px rgba(0,0,0,.2); display: flex; flex-direction: column;
        overflow: hidden; z-index: 2147483000;
      }
      .lcw-panel[hidden] { display: none; }
      .lcw-header {
        background: var(--lcw-color, #2563eb); color: #fff; padding: 12px 16px; font-weight: 600;
        display: flex; justify-content: space-between; align-items: center;
      }
      .lcw-status--online { color: #4ade80; }
      .lcw-status--offline { color: #f87171; }
      .lcw-messages { flex: 1; overflow-y: auto; padding: 12px; background: #f8fafc; }
      .lcw-msg { max-width: 80%; margin-bottom: 8px; padding: 8px 12px; border-radius: 10px; font-size: 14px; line-height: 1.35; word-wrap: break-word; }
      .lcw-msg--them { background: #e2e8f0; margin-right: auto; }
      .lcw-msg--me { background: var(--lcw-color, #2563eb); color: #fff; margin-left: auto; }
      .lcw-error { background: #fef2f2; color: #b91c1c; font-size: 12px; padding: 6px 12px; }
      .lcw-form { display: flex; border-top: 1px solid #e2e8f0; }
      .lcw-form input { flex: 1; border: none; padding: 10px 12px; font-size: 14px; outline: none; }
      .lcw-form button { border: none; background: var(--lcw-color, #2563eb); color: #fff; padding: 0 16px; cursor: pointer; font-size: 14px; }
    `
  }
})()
