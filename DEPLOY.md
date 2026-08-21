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

Скрипт ставит: Docker, Caddy, ufw (файрвол), fail2ban, автообновления
безопасности, создаёт непривилегированного пользователя `live_chat_widget`
для запуска приложения. PostgreSQL отдельно ставить не нужно — он тоже
живёт в контейнере (см. раздел 3).

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

PostgreSQL — тоже контейнер (`db` в `docker-compose.yml`), без опубликованного
порта: снаружи Docker-сети `db` не виден вообще, даже с самого хоста. Роль и
базу отдельно создавать не нужно — официальный образ `postgres` сам создаёт
их при первом старте из переменных `POSTGRES_DB`/`POSTGRES_USER`/
`POSTGRES_PASSWORD` (заполняются в шаге 4). Данные живут в именованном
Docker-volume `pgdata` — переживают пересоздание контейнера, лежат физически
в `/var/lib/docker/volumes/`.

Придумайте пароль сейчас — понадобится в шаге 4 (нужен **тот же** пароль в
двух местах env-файла: `POSTGRES_PASSWORD` и внутри `DATABASE_URL`).

## 4. Секреты приложения

```bash
sudo mkdir -p /etc/live_chat_widget
sudo cp deploy/live_chat_widget.env.example /etc/live_chat_widget/live_chat_widget.env
sudo chown root:live_chat_widget /etc/live_chat_widget/live_chat_widget.env
sudo chmod 640 /etc/live_chat_widget/live_chat_widget.env
sudo nano /etc/live_chat_widget/live_chat_widget.env
```

Группа `live_chat_widget` (не "все") может читать файл — `deploy.sh` работает от
этого пользователя и должен сам прочитать секреты перед миграцией
(`bin/migrate` не проходит через systemd и не получает `EnvironmentFile`
автоматически, в отличие от самого приложения).

Заполните: `PHX_HOST` (ваш домен), `SECRET_KEY_BASE` (`openssl rand -base64 48`),
`DATABASE_URL` (с паролем из шага 3), `TELEGRAM_BOT_TOKEN`,
`TELEGRAM_WEBHOOK_SECRET` (тот же секрет, что и в вашем `.env` локально, или
новый — просто сгенерируйте `openssl rand -hex 24` и используйте его
одинаково и в env, и при следующем `setWebhook`), `PUBLIC_BASE_URL`.

## 5. Docker

Приложение теперь пакуется в Docker-образ и собирается **не на VDS** — на
GitHub Actions (см. раздел 11), у которых полноценные amd64-раннеры без
ограничений по RAM/CPU. VDS только скачивает готовый образ и запускает его.
На сервере нужен только сам Docker:

```bash
curl -fsSL https://get.docker.com | sh
```

Systemd-юнит (`deploy/live_chat_widget.service`) для управления процессом
больше не используется — Docker сам перезапускает контейнер по политике
`restart: unless-stopped` из `docker-compose.yml`, а `docker.service`
(ставится вместе с Docker) поднимает его при перезагрузке сервера. Логи
идут в journald под тегом `live_chat_widget` — `journalctl -t live_chat_widget -f`
работает так же, как раньше работал `journalctl -u live_chat_widget -f`.

Разрешите пользователю `live_chat_widget` запускать **только** `deploy.sh`
от root (управление Docker требует root/группу docker — но именно то, какой
скрипт можно запустить, а не общий root-доступ, здесь и есть граница
безопасности):

```bash
echo 'live_chat_widget ALL=(root) NOPASSWD: /opt/live_chat_widget/src/deploy/deploy.sh' \
  | sudo tee /etc/sudoers.d/live_chat_widget
sudo chmod 440 /etc/sudoers.d/live_chat_widget
```

## 6. Caddy (HTTPS)

```bash
sudo nano deploy/Caddyfile   # замените chat.example.com на ваш домен
sudo cp deploy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Caddy не в курсе, что бэкенд теперь в контейнере — `docker-compose.yml`
использует `network_mode: host`, так что приложение слушает `127.0.0.1:4000`
точно так же, как раньше нативный процесс. Конфиг Caddy не меняется.

## 7. Первый деплой

```bash
sudo -u live_chat_widget git clone <URL_вашего_репозитория> /opt/live_chat_widget/src
sudo /opt/live_chat_widget/src/deploy/deploy.sh
```

Скрипт: подтягивает код (`git pull`, только `docker-compose.yml`/`Caddyfile`/
миграции — сам образ не собирается) → `docker compose pull` (тащит готовый
образ из ghcr.io, собранный в CI) → миграции внутри контейнера
(`docker compose run --rm app bin/migrate`) → `docker compose up -d`.

Первый раз образа в ghcr.io ещё не будет, пока не пройдёт хотя бы один
прогон CI (раздел 11) — до этого можно временно собрать образ прямо на
сервере (`docker build -t ghcr.io/<ваш-github>/live_chat_widget:latest .`)
и запустить `docker compose up -d` без `pull`, как сделал я при первом
переключении.

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

- **Мониторинг** — минимум: `journalctl -t live_chat_widget`, алерт на
  заполнение диска. При росте — Prometheus/Grafana или внешний
  uptime-монитор (UptimeRobot и т.п., бесплатный тариф хватит на старте).
- **2FA на аккаунт у VDS-провайдера и на регистратора домена** — это вне
  зоны ответственности сервера, но именно туда чаще всего ломают SaaS.

Бэкапы БД расписаны отдельно ниже, в разделе 12.

## 11. Автоматический деплой через GitHub Actions (CI/CD)

Дальше — чтобы `git push` в `main` сам гонял тесты, собирал Docker-образ и
(после этого) деплоил на сервер, без ручного `deploy.sh` каждый раз. Пайплайн
уже лежит в [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):
джоба `test` (компиляция без warning'ов, `mix format --check-formatted`,
`mix test` на Postgres-контейнере) → джоба `build` (собирает Docker-образ и
пушит в `ghcr.io/<владелец репозитория>/live_chat_widget`, используя
встроенный `GITHUB_TOKEN` — отдельный секрет для этого не нужен) → джоба
`deploy` (только если всё выше прошло и пуш именно в `main`).

**Важно про видимость образа**: по умолчанию пакет в GHCR создаётся
приватным, и `docker compose pull` на сервере не сможет его скачать без
авторизации. Проще всего сделать пакет публичным (в самом образе нет
секретов — они приезжают через env-файл только в момент запуска, а не
зашиты внутрь): GitHub → ваш профиль → Packages → `live_chat_widget` →
Package settings → Change visibility → Public. Либо, если хотите оставить
приватным, — добавляем на сервер `docker login ghcr.io` с токеном (лишний
секрет для хранения, поэтому по умолчанию рекомендую первый вариант).

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
command="sudo /opt/live_chat_widget/src/deploy/deploy.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA...вставьте содержимое deploy_key.pub... github-actions-deploy
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

## 12. База данных: безопасность, бэкапы, репликация

### Что уже защищено по умолчанию

- **Postgres не публикует порт вообще** (`db` в `docker-compose.yml` без
  секции `ports:`) — недостижим не только снаружи сервера, но и с самого
  хоста: только контейнер `app` на той же Docker-сети может к нему
  подключиться. Строже, чем стандартное "слушает только 127.0.0.1".
- **Парольная аутентификация scram-sha-256** — дефолт официального образа
  `postgres`, не `trust`, не устаревший `md5`.
- **Наименьшие права**: роль `live_chat_widget` — не суперпользователь,
  владеет только своей базой `live_chat_widget_prod`, не видит другие БД
  на сервере и не может их создавать/удалять.
- **Пароль роли** — сгенерирован случайно (`openssl rand`), хранится только
  в `/etc/live_chat_widget/live_chat_widget.env` (права `640`,
  `root:live_chat_widget`), не в git.

### Бэкапы — что настроено прямо сейчас

`deploy/backup_db.sh` — ежедневно в 03:00 по cron (root):
`pg_dump -Fc` (сжатый, самодостаточный формат) → `/var/backups/live_chat_widget/`,
хранятся последние 14 дней, старые удаляются автоматически. Лог —
`/var/log/live_chat_widget-backup.log`.

**Восстановление из бэкапа** (на этом же или другом сервере — контейнер `db`
должен быть поднят, `docker compose up -d db`):

```bash
docker compose -f /opt/live_chat_widget/src/docker-compose.yml exec -T db \
  pg_restore -U live_chat_widget -d live_chat_widget_prod --clean --if-exists \
  < /var/backups/live_chat_widget/live_chat_widget_prod_ДАТА.dump
```

Проверить, что бэкап реально восстанавливается — стоит делать периодически
руками (бэкап, который никто не пробовал восстановить, не бэкап).

### Копия за пределами этого сервера — то, чего пока нет

Сейчас бэкапы лежат **на том же VDS**. Если сгорит диск/сервер — бэкапы
сгорят с ним. Варианты (нужно ваше решение, я не завожу это без вас —
требуются either доступ к другому серверу, either платный S3-бакет):

1. **Снапшоты у вашего VDS-провайдера** — самый простой вариант, если
   провайдер это предлагает (часто есть в панели управления, иногда платно).
   Не требует моей настройки — включается на стороне провайдера.
2. **rclone → S3-совместимое хранилище** (Selectel S3, Yandex Object Storage,
   Backblaze B2, Cloudflare R2 и т.п.): даёте бакет + ключи доступа, я
   добавляю в `backup_db.sh` шаг `rclone copy` после каждого дампа.
   Копейки в месяц при таком объёме БД.
3. **scp на другую вашу машину** по cron — бесплатно, но требует, чтобы
   та машина была доступна по сети и постоянно включена.

Скажите, какой вариант подходит — донастрою `backup_db.sh` под него.

### Репликация — когда она нужна и что это на самом деле означает

Бэкапы защищают от потери данных ("вчера всё было, сегодня всё сломалось —
откатились"), но не от **простоя**: если сервер упал, восстановление из
дампа на новый сервер — это минуты-десятки минут, а не секунды. Настоящая
репликация — это **отдельный второй сервер** с Postgres, куда данные льются
непрерывно, и который может подхватить нагрузку почти сразу.

Что это требует на практике:

- **Второй VDS** (ещё один сервер — сейчас его нет, для теста был выделен
  только один).
- На нём — Postgres той же версии, `wal_level = replica` на основном сервере,
  создание реплики через `pg_basebackup`, дальше — потоковая репликация
  (WAL летит на реплику практически в реальном времени).
- Дальше нужен план на "а что если основной сервер упал" — переключение
  реплики в primary руками или через инструмент типа Patroni (последнее —
  уже скорее для serious production, не для MVP).

Для текущего масштаба проекта (MVP/тест) я бы **не стал** поднимать второй
сервер прямо сейчас — это ощутимая дополнительная сложность и стоимость
ради defense против сценария "сервер полностью умер", который бэкапы (пусть
и с простоем в восстановлении) уже покрывают. Разумный следующий шаг —
именно офсайт-копия бэкапов (пункт выше), а не полноценная репликация.
Если/когда появится второй сервер и реальная нагрузка — возвращаемся к этому
разговору, там ещё есть промежуточный вариант (WAL-G/pgBackRest — льют WAL
в S3 непрерывно, восстановление на любой момент времени без второго живого
сервера) — дешевле репликации, но чуть сложнее, чем просто `pg_dump` по
крону.

### Переезд на другой сервер

Раз и приложение, и БД теперь в Docker — переезд на новый VDS выглядит так:

1. Новый сервер: `curl -fsSL https://get.docker.com | sh`, поставить Caddy,
   скопировать `docker-compose.yml`, `Caddyfile`, `/etc/live_chat_widget/live_chat_widget.env`.
2. `docker compose up -d db`, дождаться, пока контейнер станет healthy.
3. Восстановить туда последний бэкап (команда выше).
4. `docker compose up -d` (поднимает `app`), проверить, что всё отвечает.
5. Переключить DNS-A-запись на новый IP.

Никакой возни с "какая версия Postgres/Erlang/Elixir стояла на старом
сервере" — версии зафиксированы в образах, а не в состоянии конкретной
машины. Это и есть главный практический выигрыш от контейнеризации БД,
о котором вы спрашивали.

## Что сейчас в проде

Задеплоено и работает на `https://chatlio.ru` — см. отчёт в чате о
том, как именно это было сделано, что было исправлено по пути, и что
осталось как открытый вопрос (в первую очередь — сетевая блокировка
Telegram с этого сервера).
