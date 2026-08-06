# Деплой на VDS

Пошаговый гайд: сервер → HTTPS → приложение → защита. Готовые конфиги лежат в
[`deploy/`](deploy/): `setup_server.sh`, `deploy.sh`, `Caddyfile`,
`live_chat_widget.service`, `live_chat_widget.env.example`.

## 0. Что нужно подготовить

| Что | Где взять |
|---|---|
| VDS: 1-2 vCPU, 2-4 GB RAM, Ubuntu 24.04 LTS | любой провайдер (Hetzner, Timeweb, Selectel и т.п.) |
| Домен | купить, например `chat.yourdomain.com` |
| DNS A-запись | `chat.yourdomain.com → IP_вашего_VDS` (в панели регистратора/DNS-провайдера) |
| SSH-ключ | `ssh-keygen -t ed25519` на своей машине, если ещё нет |
| Telegram bot token | уже есть (создан через @BotFather) |

Домен должен успеть распространиться (обычно 5–30 минут) до того, как Caddy
попытается получить сертификат — иначе Let's Encrypt не сможет провалидировать
домен.

## 1. HTTPS — как это работает

Мы используем **Caddy** как reverse proxy перед приложением: он сам получает и
продлевает бесплатный сертификат Let's Encrypt, без единой ручной команды —
это надёжнее и проще, чем nginx + certbot (нет отдельного cron на обновление
сертификата, меньше шансов что-то сломать).

Схема: `Browser --HTTPS(443)--> Caddy --HTTP(127.0.0.1:4000)--> Phoenix`.
Приложению не нужно ничего знать про сертификаты — оно всегда общается по
голому HTTP с localhost, шифрование терминируется на Caddy.

Если предпочитаете nginx + certbot — тоже нормальный вариант, просто больше
движущихся частей (сам nginx-конфиг + `certbot renew` по таймеру). Если нужно,
могу отдельно расписать этот путь, но по умолчанию рекомендую Caddy.

## 2. Первичная настройка сервера

Зайдите на сервер по SSH (`ssh root@IP_сервера`), склонируйте репозиторий во
временную папку и запустите скрипт:

```bash
git clone <URL_вашего_репозитория> /tmp/live_chat_widget
cd /tmp/live_chat_widget
sudo bash deploy/setup_server.sh
```

Скрипт ставит: Erlang/Elixir, PostgreSQL, Caddy, ufw (файрвол), fail2ban,
автообновления безопасности, создаёт непривилегированного пользователя
`live_chat_widget` для запуска приложения.

**Важно про SSH:** скрипт не трогает SSH-конфиг автоматически. После него —
убедитесь, что вход по ключу работает **в отдельном терминале**, не закрывая
текущую сессию, и только потом в `/etc/ssh/sshd_config` выставьте:

```
PasswordAuthentication no
PermitRootLogin no
```

и `sudo systemctl restart ssh`. Если сделать это раньше, чем проверили ключ —
есть риск закрыть себе доступ к серверу.

## 3. База данных

```bash
sudo -u postgres psql -c "CREATE ROLE live_chat_widget WITH LOGIN PASSWORD 'придумайте_пароль';"
sudo -u postgres psql -c "CREATE DATABASE live_chat_widget_prod OWNER live_chat_widget;"
```

## 4. Секреты приложения

```bash
sudo mkdir -p /etc/live_chat_widget
sudo cp deploy/live_chat_widget.env.example /etc/live_chat_widget/live_chat_widget.env
sudo chmod 600 /etc/live_chat_widget/live_chat_widget.env
sudo chown root:root /etc/live_chat_widget/live_chat_widget.env
sudo nano /etc/live_chat_widget/live_chat_widget.env
```

Заполните: `PHX_HOST` (ваш домен), `SECRET_KEY_BASE` (`openssl rand -base64 48`),
`DATABASE_URL` (с паролем из шага 3), `TELEGRAM_BOT_TOKEN`,
`TELEGRAM_WEBHOOK_SECRET` (тот же секрет, что и в вашем `.env` локально, или
новый — просто сгенерируйте `openssl rand -hex 24` и используйте его
одинаково и в env, и при следующем `setWebhook`), `PUBLIC_BASE_URL`.

## 5. Systemd-сервис

```bash
sudo cp deploy/live_chat_widget.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable live_chat_widget
```

Разрешите пользователю `live_chat_widget` перезапускать именно этот сервис
(и только его — не root-доступ целиком), чтобы `deploy.sh` мог сам
рестартовать процесс после сборки:

```bash
echo 'live_chat_widget ALL=(root) NOPASSWD: /usr/bin/systemctl restart live_chat_widget, /usr/bin/systemctl status live_chat_widget' \
  | sudo tee /etc/sudoers.d/live_chat_widget
```

## 6. Caddy (HTTPS)

```bash
sudo nano deploy/Caddyfile   # замените chat.example.com на ваш домен
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

## 7. Первый деплой

```bash
sudo -u live_chat_widget git clone <URL_вашего_репозитория> /opt/live_chat_widget/src
sudo -u live_chat_widget bash /opt/live_chat_widget/src/deploy/deploy.sh
```

Скрипт: подтягивает код → собирает assets (JS-виджет + операторская панель)
→ собирает release → прогоняет миграции → рестартует systemd-сервис.

Проверка: `curl -I https://ваш-домен` должен вернуть `200`, и
`sudo journalctl -u live_chat_widget -f` — смотреть логи вживую.

## 8. Переключить Telegram webhook на прод-домен

```bash
curl -s "https://api.telegram.org/bot<ТОКЕН>/setWebhook" \
  -d "url=https://ваш-домен/webhooks/telegram" \
  -d "secret_token=<тот же TELEGRAM_WEBHOOK_SECRET, что в env>"
```

После этого ngrok и локальный сервер для теста Telegram больше не нужны —
всё летит напрямую на прод.

## 9. Как деплоить обновления дальше

```bash
sudo -u live_chat_widget bash /opt/live_chat_widget/src/deploy/deploy.sh
```

Каждый деплой — новая папка в `releases/`, старые (кроме последних 5)
удаляются автоматически. Если релиз сломался — можно быстро откатиться,
переключив симлинк `current` на предыдущую папку в `releases/` и рестартнув
сервис.

## 10. Защита сервера и сайта — что уже сделано и что проверять

Уже настроено скриптами выше:

- **ufw**: открыты только 22 (SSH), 80, 443 — всё остальное закрыто снаружи
  (в т.ч. порт 4000 приложения и 5432 Postgres не торчат наружу).
- **fail2ban**: банит IP после нескольких неудачных попыток SSH-логина.
- **unattended-upgrades**: security-патчи ОС ставятся автоматически.
- **SSH только по ключу**, root-логин выключен (после шага 2).
- **systemd hardening**: процесс приложения запущен без root, с
  `ProtectSystem=strict`, `NoNewPrivileges`, `PrivateTmp` и т.д. — даже если
  в приложении найдётся уязвимость, у процесса минимум прав на систему.
- **HTTPS everywhere**: `force_ssl` уже включён в `config/prod.exs`, плюс
  HSTS-заголовок из Caddyfile.
- **Webhook подписан секретом**: `/webhooks/telegram` проверяет
  `X-Telegram-Bot-Api-Secret-Token`, поддельные запросы отклоняются.
- **Анти-флуд**: рейт-лимиты на сообщения/новых визитеров уже в коде
  (`LiveChatWidget.RateLimit`).
- **Секреты не в git**: `.env` и `/etc/live_chat_widget/*.env` — вне
  репозитория, `chmod 600`.

Что стоит сделать дополнительно (не входит в скрипты, но важно):

- **Бэкапы БД** — cron с `pg_dump`, например ежедневно в 03:00, храня
  последние ~14 копий, желательно копировать за пределы самого VDS
  (S3-совместимое хранилище, другой сервер). Спрошу отдельно, если нужно —
  могу написать скрипт бэкапа и настроить его.
- **Мониторинг** — минимум: `journalctl -u live_chat_widget`, алерт на
  заполнение диска. При росте — Prometheus/Grafana или внешний
  uptime-монитор (UptimeRobot и т.п., бесплатный тариф хватит на старте).
- **2FA на аккаунт у VDS-провайдера и на регистратора домена** — это вне
  зоны ответственности сервера, но именно туда чаще всего ломают SaaS.

## 11. Автоматический деплой через GitHub Actions (CI/CD)

Дальше — чтобы `git push` в `main` сам гонял тесты и (после этого) деплоил на
сервер, без ручного `deploy.sh` каждый раз. Пайплайн уже лежит в
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml): джоба `test`
(компиляция без warning'ов, `mix format --check-formatted`, `mix test` на
Postgres-контейнере) → джоба `deploy` (только если `test` прошла и пуш именно
в `main`).

### Модель угроз и почему так, а не проще

Самый простой вариант — положить приватный SSH-ключ от root в GitHub Secrets
и дать CI `ssh root@server rm -rf ... && ...`. Это плохая идея: если секрет
когда-нибудь утечёт (скомпрометированный runner, баг в самом GitHub Actions,
неаккуратный `echo` в логах) — у атакующего сразу полный root на сервере.
Ниже — тот же результат (автодеплой одной кнопкой/пушем), но с урезанным
периметром на каждом шаге:

| Риск | Что делаем |
|---|---|
| Утечка приватного ключа из GitHub Secrets | Ключ логинится **не под root**, а под `live_chat_widget` — тем же пользователем без прав что и так уже есть у приложения |
| Утечка ключа → произвольные команды на сервере | `authorized_keys` с `command=...` — SSH этим ключом может выполнить **только** `deploy.sh`, что бы ни попросили с клиента |
| MITM при первом подключении CI к серверу | Отпечаток хоста (`known_hosts`) вписан заранее как секрет, а не доверяется автоматически при каждом запуске (`StrictHostKeyChecking=yes`) |
| Скомпрометированный PR из форка запускает деплой | `deploy` не триггерится на `pull_request`, только на `push` в `main`; форки в принципе не получают секреты в GitHub Actions |
| Один плохой коммит в `main` — и сразу в проде | GitHub Environment `production` с обязательным ревью (см. ниже) — деплой ставится на пауза и ждёт вашего клика |
| GITHUB_TOKEN с лишними правами | `permissions: contents: read` явно прописан в workflow — токену нечего портить, даже если сам workflow скомпрометирован |

### Шаг 1 — отдельный ключ только для деплоя

На своей машине (не на сервере):

```bash
ssh-keygen -t ed25519 -f ./deploy_key -C "github-actions-deploy" -N ""
```

Получите два файла: `deploy_key` (приватный — уйдёт в GitHub Secrets) и
`deploy_key.pub` (публичный — на сервер).

### Шаг 2 — форс-команда на сервере

На сервере, под пользователем `live_chat_widget`:

```bash
sudo -u live_chat_widget mkdir -p /home/live_chat_widget/.ssh
sudo -u live_chat_widget tee -a /home/live_chat_widget/.ssh/authorized_keys <<'EOF'
command="/opt/live_chat_widget/src/deploy/deploy.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA...вставьте содержимое deploy_key.pub... github-actions-deploy
EOF
sudo chmod 700 /home/live_chat_widget/.ssh
sudo chmod 600 /home/live_chat_widget/.ssh/authorized_keys
sudo chown -R live_chat_widget:live_chat_widget /home/live_chat_widget/.ssh
```

Ключевая часть — `command="..."` в начале строки: неважно, что именно попросит
выполнить подключившийся по этому ключу клиент, сервер всегда запустит
`deploy.sh`. Обычный интерактивный шелл этим ключом получить нельзя.

### Шаг 3 — зафиксировать отпечаток сервера

С любой машины, которой вы доверяете (например, той же, где генерировали ключ):

```bash
ssh-keyscan -H ваш-домен-или-IP > known_hosts_pinned
cat known_hosts_pinned
```

Содержимое этого файла целиком пойдёт в секрет `DEPLOY_KNOWN_HOSTS` — так CI
будет доверять именно этому конкретному отпечатку сервера, а не тому, что
ему подсунут при первом запуске.

### Шаг 4 — секреты в GitHub

Repo → Settings → Secrets and variables → Actions → New repository secret:

| Секрет | Значение |
|---|---|
| `DEPLOY_SSH_KEY` | содержимое `deploy_key` (приватный, целиком, с `-----BEGIN...-----`) |
| `DEPLOY_KNOWN_HOSTS` | содержимое `known_hosts_pinned` из шага 3 |
| `DEPLOY_USER` | `live_chat_widget` |
| `DEPLOY_HOST` | ваш домен или IP сервера |

После этого удалите `deploy_key` и `deploy_key.pub` с локальной машины (или
храните в менеджере паролей) — в открытом виде на диске он не нужен.

### Шаг 5 — approval-гейт (рекомендую)

Repo → Settings → Environments → New environment → назовите `production` →
включите **Required reviewers** и укажите себя. Теперь после успешных тестов
джоба `deploy` встанет на пауза и попросит подтверждение в интерфейсе GitHub
перед тем, как реально тронуть сервер — это тот компромисс между «полностью
автоматически» и «безопасно», о котором вы спрашивали. Без этого шага деплой
на `main` будет полностью автоматическим (что тоже нормально, если вам важна
именно скорость, а ревью кода вы делаете через PR).

### Шаг 6 — защита ветки `main`

Repo → Settings → Branches → Add rule для `main`:

- Require a pull request before merging (+ хотя бы 1 approval, если работаете
  не один).
- Require status checks to pass before merging → отметьте джобу `test`.
- Do not allow force pushes, Do not allow deletions.

Теперь в `main` ничего не попадёт мимо CI, а значит и деплоя ничего не
попадёт непроверенным.

### Как это работает после настройки

```
git push origin main
        │
        ▼
GitHub Actions: test  (компиляция, format, mix test на Postgres-контейнере)
        │ (только если зелёно)
        ▼
GitHub Actions: deploy  (ждёт approval, если настроен Environment)
        │
        ▼
ssh (forced command) → deploy.sh на сервере →
  git pull → mix deps.get → assets.deploy → mix release → migrate → systemctl restart
```

Проверить: `Actions` таб в GitHub репозитории — там видно каждый запуск,
логи джобы `deploy` покажут, если что-то пошло не так (сервер недоступен,
`deploy.sh` завершился с ошибкой и т.п.) — сам деплой на сервере в этом
случае просто не произойдёт, systemd продолжит гонять старую версию.

### Если ключ скомпрометирован

Удалите строку из `authorized_keys` на сервере (`sudo -u live_chat_widget
nano /home/live_chat_widget/.ssh/authorized_keys`), сгенерируйте новую пару
ключей (Шаг 1) и обновите секрет `DEPLOY_SSH_KEY`. Старый ключ сразу
перестаёт работать в момент удаления строки — никаких прав уровня root он и
так не давал.

## Что нужно от вас, чтобы я сам довёл деплой до конца

Если хотите, чтобы я выполнил эти шаги за вас, а не вы руками по гайду выше —
дайте:

1. IP сервера и SSH-доступ (лучше: создайте отдельного sudo-пользователя с
   моим/вашим публичным ключом, не root-пароль).
2. Домен, который будет указывать на сервер.
3. Явное подтверждение, что можно выполнять команды на этом сервере
   (это разово, для этой задачи — я не буду это считать постоянным
   разрешением на будущее).

Либо просто следуйте гайду сами — он самодостаточен, и я на связи, если
что-то пойдёт не так на конкретном шаге.
