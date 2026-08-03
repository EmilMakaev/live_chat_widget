# Live Chat Widget

Виджет онлайн-чата для сайтов клиентов с пересылкой сообщений операторам в
Telegram (и заделом на другие мессенджеры) + веб-панель оператора на
Phoenix LiveView. Elixir/Phoenix, Postgres, Oban.

## Содержание

- [Как это работает](#как-это-работает)
- [Структура кода](#структура-кода--что-где-лежит)
- [Модель данных](#модель-данных)
- [Как запустить проект с нуля](#как-запустить-проект-с-нуля)
- [Как проверить интеграцию с Telegram локально](#как-проверить-интеграцию-с-telegram-локально)
- [Где что смотреть при отладке](#где-что-смотреть-при-отладке)
- [Переменные окружения](#переменные-окружения)
- [Известные ограничения и что дальше](#известные-ограничения-и-что-дальше)
- [Деплой](#деплой)

## Как это работает

```
Посетитель на сайте клиента
        │  пишет в виджет (assets/js/widget.js)
        ▼
WebSocket  →  WidgetSocket/WidgetChannel  (lib/live_chat_widget_web/channels/)
        │  анти-флуд (LiveChatWidget.RateLimit) → Chat.receive_visitor_message/2
        ▼
   Postgres (conversations, messages)  ──PubSub──▶  OperatorLive.Dashboard (LiveView)
        │
        ▼  Oban job (по одному на каждый messenger_channel сайта)
MessengerDispatchWorker → Messengers.Registry → Messengers.Telegram → Telegram Bot API
        │
        ▼
Оператор отвечает в Telegram (Reply на сообщение)
        │
        ▼
TelegramWebhookController → Chat.find_conversation_by_channel_reply/2
        │
        ▼
Chat.send_operator_message/2 → Postgres → PubSub → обратно в виджет посетителя
                                                   → и в LiveView-панель оператора
```

Оператор может отвечать **и из Telegram, и из веб-панели** — обе стороны
пишут в один и тот же `Chat.send_operator_message/2`, поэтому история и
статус диалога всегда синхронны независимо от канала.

## Структура кода — что где лежит

### Бизнес-логика (`lib/live_chat_widget/`)

| Файл | Что делает |
|---|---|
| `accounts.ex` + `accounts/*` | Мульти-тенантность: `Account` (компания-клиент), `Membership` (кто из `Identity.User` в какой компании и с какой ролью), `Site` (сайт клиента + `site_token` для виджета), `MessengerChannel` (привязка Telegram-чата/будущих мессенджеров к компании/оператору) |
| `chat.ex` + `chat/*` | Ядро, не знающее про конкретные мессенджеры: `Visitor` (посетитель сайта), `Conversation` (диалог, статус open/claimed/closed), `Message`, `MessengerMessageRef` (маппинг «какому диалогу соответствует конкретное сообщение в Telegram» — по нему разбираются Reply от оператора), `PubSub` (топики для живых обновлений) |
| `messengers/adapter.ex` | Behaviour, который должен реализовать любой мессенджер: `send_message/2`, `verify_webhook/1`, `parse_webhook/1`, `render/2` |
| `messengers/telegram.ex` | Единственная реализация адаптера сейчас. Вся Telegram-специфика (формат сообщений, HTTP к Bot API, разбор вебхука) — здесь и только здесь |
| `messengers/registry.ex` | `type` (`:telegram`) → модуль-адаптер. Чтобы добавить WhatsApp/Slack/Viber — новый модуль с этим behaviour + одна строчка сюда |
| `messengers/incoming_event.ex` | Нормализованное событие от любого мессенджера (`:connect` или `:reply`) — остальной код не видит форматы конкретных API |
| `workers/messenger_dispatch_worker.ex` | Oban-воркер: доставляет одно сообщение в один канал, с ретраями. Отвязывает доставку в Telegram от HTTP-запроса, который её вызвал |
| `rate_limit.ex` | Анти-флуд/анти-спам (Hammer, ETS): лимиты на сообщения от посетителя и на создание новых "гостей" по IP |
| `identity.ex` + `identity/*` | Сгенерировано `mix phx.gen.auth` — логин операторов (email+пароль или magic link) |

### Web-слой (`lib/live_chat_widget_web/`)

| Файл | Что делает |
|---|---|
| `channels/widget_socket.ex`, `channels/widget_channel.ex` | Публичный (без авторизации) WebSocket для встраиваемого виджета. Вся защита — по `site_token` + rate limit, не по Origin (виджет обязан коннектиться с любого сайта клиента) |
| `controllers/telegram_webhook_controller.ex` | `POST /webhooks/telegram` — проверяет секретный токен, разбирает событие, привязывает Telegram-чат (`/start connect_...`) или роутит Reply оператора в `Chat` |
| `live/operator_live/dashboard.ex` | Панель оператора: список диалогов + тред + ответ, обновляется вживую через `Chat.PubSub` (LiveView streams, без перезагрузки страницы) |
| `endpoint.ex` | `/widget_socket` смонтирован с `check_origin: false` — намеренно, см. комментарий в файле |

### Фронтенд виджета (`assets/js/widget.js`)

Отдельный esbuild-бандл (профиль `widget` в `config/config.exs`, не смешан с
`app.js` панели). Vanilla JS, Shadow DOM для изоляции стилей от сайта
клиента, ~9 КБ gzip. Хранит `visitor_token` в `localStorage`, коннектится к
`/widget_socket`, шлёт/принимает сообщения.

### Данные (`priv/repo/migrations/`, `priv/repo/seeds.exs`)

Миграции — по одной сущности на файл, в порядке создания. `seeds.exs`
создаёт демо-оператора + компанию + сайт для локальной разработки.

### Деплой (`deploy/`, `DEPLOY.md`)

Готовые конфиги и пошаговый гайд по разворачиванию на VDS — см. отдельный
раздел [Деплой](#деплой) ниже.

## Модель данных

```
accounts ─┬─< account_memberships >─┬─ users (identity, phx.gen.auth)
          │                         │
          ├─< sites (site_token)    │
          │        └─< visitors ─< conversations >─ users (claimed_by)
          │                              └─< messages
          └─< messenger_channels (type, external_id=telegram chat_id, user_id)
                       └─< messenger_message_refs >─ messages
```

- **`site_token`** — публичный, зашит в JS на сайте клиента. Не секрет, доступ
  контролируется рейт-лимитами, не секретностью токена.
- **`messenger_channels.connect_code`** — одноразовый код для привязки Telegram
  (аналог `?start=connect_42` из ТЗ, но случайный токен вместо предсказуемого
  ID компании — не даёт перебором угадать чужой код).
- **`messenger_message_refs`** — почему это нужно: когда оператор жмёт Reply в
  Telegram, у нас есть только `messenger_channel_id` (чей это чат) и
  `reply_to_message_id` (на какое сообщение ответили). Эта таблица — единственный
  способ понять, к какому диалогу это относится. Хранится в БД, не в памяти —
  переживает рестарт/деплой сервера.

## Как запустить проект с нуля

Предполагается macOS с Homebrew (на Linux — те же шаги, `apt`/`brew` под capot
разные, но `mix`-команды идентичны).

```bash
brew install elixir postgresql@16
brew services start postgresql@16

cd live_chat_widget
mix deps.get
mix esbuild.install --if-missing
mix tailwind.install --if-missing

cp .env.example .env
# впишите в .env: TELEGRAM_BOT_TOKEN (от @BotFather),
# TELEGRAM_WEBHOOK_SECRET (любая случайная строка: `openssl rand -hex 24`)

mix ecto.setup   # создаёт БД, накатывает миграции, гоняет seeds.exs
mix phx.server
```

Дальше:

- **Виджет**: [http://localhost:4000/demo.html](http://localhost:4000/demo.html)
  — тестовая страница с виджетом (`site_token` в `priv/static/demo.html`
  соответствует сайту, который создали seeds).
- **Панель оператора**: [http://localhost:4000/users/log-in](http://localhost:4000/users/log-in)
  — логин `operator@example.com` / `DemoPassword123!` (из `seeds.exs`), после
  входа редирект на `/dashboard`.

Без Telegram-токена всё выше уже работает (виджет ↔ панель оператора), просто
сообщения никуда не будут дублироваться в Telegram, пока не пройдёте шаги
ниже.

## Как проверить интеграцию с Telegram локально

Telegram шлёт вебхуки на публичный HTTPS-адрес, поэтому локально нужен туннель.

```bash
ngrok http 4000
```

Возьмите `https://xxxx.ngrok-free.app` из вывода ngrok и:

```bash
mix telegram.webhook https://xxxx.ngrok-free.app
mix chat.connect_telegram operator@example.com
```

Вторая команда напечатает ссылку вида `https://t.me/your_bot?start=connect_...`
— откройте её в Telegram и нажмите Start. После этого:

- сообщения из виджета/панели будут дублироваться оператору в Telegram;
- Reply на такое сообщение в Telegram уйдёт обратно в виджет посетителя и
  появится в панели.

При каждом перезапуске ngrok адрес меняется — повторите
`mix telegram.webhook <новый URL>` (`chat.connect_telegram` повторять не нужно,
привязка живёт в БД).

## Где что смотреть при отладке

| Что проверить | Как |
|---|---|
| Логи сервера | вывод `mix phx.server` (в проде — `journalctl -u live_chat_widget -f`, см. DEPLOY.md) |
| Сообщения/диалоги в БД | `psql live_chat_widget_dev -c "SELECT * FROM messages ORDER BY id DESC LIMIT 20;"` |
| Доставка в мессенджеры | `SELECT id, state, worker, errors, args FROM oban_jobs ORDER BY id DESC;` — `state` = `completed`/`retryable`/`discarded`, `errors` — стек ошибки, если не доставилось |
| Статус Telegram-вебхука | `curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"` — смотрите `last_error_message` и `pending_update_count` |
| Ошибки в браузере (виджет) | консоль браузера — `widget.js` логирует туда `[chat-widget] ...` |
| Метрики/дашборд Phoenix | [http://localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard) (только dev) |
| Почта разработки (magic link, подтверждение email) | [http://localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox) |

## Переменные окружения

Локально — файл `.env` в корне (не в git, см. `.env.example`), в проде —
`/etc/live_chat_widget/live_chat_widget.env` (см. `deploy/live_chat_widget.env.example`).

| Переменная | Для чего |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Токен бота от @BotFather |
| `TELEGRAM_WEBHOOK_SECRET` | Секрет, которым Telegram подписывает вебхуки (`X-Telegram-Bot-Api-Secret-Token`) — проверяется в `TelegramWebhookController`, защита от поддельных запросов |
| `PUBLIC_BASE_URL` | Текущий публичный адрес (ngrok/прод-домен) — пока используется только человеком (для ссылок), не самим кодом |
| `SECRET_KEY_BASE`, `DATABASE_URL`, `PHX_HOST`, `PORT`, `POOL_SIZE` | Стандартные для Phoenix-релиза, нужны только в проде — см. DEPLOY.md |

## Известные ограничения и что дальше

Честно о том, чего пока нет — чтобы не было сюрпризов:

- **Реализован только Telegram.** Архитектура (`Messengers.Adapter` behaviour)
  готова под WhatsApp/Slack/Viber, но сами модули не написаны — это отдельная
  задача на 1-2 дня на мессенджер, как и написано в исходном ТЗ.
- **`routing_strategy` на сайте (`broadcast`/`round_robin`/`department`) —
  задел в схеме, реально работает только `broadcast`** (шлём всем активным
  каналам компании, пока диалог не забрал первый ответивший оператор).
  Round-robin и явный выбор отдела на виджете — не реализованы.
- **Нет UI для подключения Telegram** («Подключить Telegram» кнопка из ТЗ) —
  сейчас это `mix chat.connect_telegram email`. Нужно добавить в панель
  оператора, когда появится экран настроек компании/сайта.
- **Нет UI для создания компаний/сайтов** — тоже через `seeds.exs`/IEx.
  Простая форма регистрации + "добавить сайт" — следующий логичный шаг.
- **Вложения (фото/файлы)** — не поддерживаются ни в виджете, ни в Telegram-адаптере.
- **PWA** — панель оператора уже устанавливается на телефон («Добавить на
  экран Домой», см. `priv/static/manifest.webmanifest`), но без push-уведомлений
  (нужен Web Push + VAPID — отдельная задача) и без offline-режима (для
  чата в реальном времени офлайн не так уж и осмыслен).
- **`OperatorLive.Dashboard` не использует `<Layouts.app>`** — сознательно
  (это полноэкранный inbox, а не центрированная страница вроде настроек),
  но это отступление от общего соглашения проекта (см. `AGENTS.md`), стоит
  иметь в виду, если будете добавлять новые полноэкранные экраны рядом.

## Деплой

Подробный пошаговый гайд (VDS, HTTPS через Caddy, systemd, безопасность) —
в [DEPLOY.md](DEPLOY.md). Готовые конфиги — в [`deploy/`](deploy/).
