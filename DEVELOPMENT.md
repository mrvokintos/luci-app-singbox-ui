# Development guide

Карта проекта для разработчиков, которые впервые открыли `luci-app-singbox-ui`. Здесь описаны архитектура, runtime-пути, установщики, сборка, тесты и правила релизов. Реальные пользовательские конфиги, ключи и ссылки в этот файл не входят.

## Назначение

`luci-app-singbox-ui` — лёгкое LuCI-приложение для управления уже установленным `sing-box` на OpenWrt.

Основные принципы:

- пакет LuCI не зависит от пакета `sing-box`;
- ядро ставится отдельным скриптом и бывает Original, Extended или Clean;
- UI сканирует все `/etc/sing-box/*.json`;
- редактирование не перезаписывает файлы в фоне;
- применение именованного файла копирует его в `/etc/sing-box/config.json`, сохраняя исходник;
- до явной команды пользователя публикуются только RC/pre-release версии.

## Структура

| Путь | Ответственность |
| --- | --- |
| `luci-app-singbox-ui/Makefile` | Метаданные пакета и внутренняя версия |
| `luci-app-singbox-ui/htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js` | Экран LuCI, HTML/CSS, файлы, сервис, редакторы |
| `luci-app-singbox-ui/htdocs/luci-static/resources/singbox-ui/share-link.js` | Парсер VLESS/VMess/Trojan/Hysteria и других ссылок |
| `luci-app-singbox-ui/root/usr/libexec/singbox-ui-helper` | Ограниченные privileged-операции с файлами |
| `luci-app-singbox-ui/root/etc/singbox-ui/template.json` | Legacy/default-шаблон, conffile OpenWrt |
| `luci-app-singbox-ui/root/usr/share/rpcd/acl.d/luci-app-singbox-ui.json` | Права LuCI/rpcd |
| `luci-app-singbox-ui/root/usr/sbin/singbox-ui` | Настройка роутера: полноэкранное меню, вопросы по очереди, `--yes`. `singbox-ui-setup` — ссылка на неё (старое имя) |
| `luci-app-singbox-ui/root/usr/share/singbox-ui/setup/*.sh` | Модули setup: `source` (адреса GitHub и репозитория, для форков), `ui` (вывод, `ui_choose`), `tui` (полноэкранный режим), `pkg` (APK/IPK, архитектура), `repo` (ключи и фиды), `core` (ядро), `system` (сервис, TUN, IPv6, сеть), `autoupdate` (cron), `i18n` |
| `luci-app-singbox-ui/root/usr/libexec/singbox-ui-autoupdate` | Задача cron: обновление панели и ядра с проверкой config.json |
| `luci-app-singbox-ui/root/usr/libexec/singbox-ui-mode-switch` | Настройка и удаление TUN, очистка старого TPROXY |
| `install.sh` | Загрузчик: репозиторий, пакет, запуск `singbox-ui` |
| `other/scripts/install-singbox*.sh` | Устаревшие обёртки над `install.sh` для старых ссылок |
| `Dockerfile` | Сборка IPK/APK в официальном OpenWrt SDK (`openwrt/sdk`) |
| `.github/workflows/build_luci-app-singbox-ui_from_tag.yml` | Ручная сборка и публикация GitHub Release (Release/Pre-release) |
| `.github/workflows/build_luci-app-singbox-ui_from_pr.yml` | Автосборка артефактов при коммите/PR |
| `tests/share-link.test.js` | Тесты parser |
| `tests/helper.test.sh` | Тесты helper и защиты путей |
| `tests/setup.test.sh` | Тесты модулей setup на фейковом корне (`SBUI_ROOT`), идут и в busybox |
| `tests/version.test.sh` | `UI_VERSION` в JS совпадает с `PKG_VERSION` |

## Runtime-пути

```text
/etc/sing-box/config.json              активная копия для сервиса
/etc/sing-box/*.json                    именованные конфиги
/etc/singbox-ui/template.json           стандартный legacy-шаблон
/etc/singbox-ui/templates/*.json        дополнительные шаблоны
/etc/singbox-ui/active-template         выбранный шаблон генератора
/etc/singbox-ui/active-config           последний применённый конфиг
/etc/singbox-ui/log-clear-marker        persistent-маркер очищенного журнала
/usr/libexec/singbox-ui-helper          helper
/usr/bin/sing-box                       отдельно установленное ядро
/etc/init.d/sing-box                    init-скрипт
```

## UI и конфиги

Основной JS намеренно самодостаточный: HTML и CSS находятся внутри `singbox-ui.js`. ACE удалён ради размера пакета; подсветка JSON сделана лёгким overlay из `textarea` и `pre`.

`listConfigs()` читает `/etc/sing-box` через `fs.list()` и принимает только обычные файлы с именем `.json`.

Операции списка:

- `Apply` копирует выбранный файл в `config.json`, записывает `active-config` и перезапускает сервис;
- `Edit` загружает файл, но пишет только по `Save`;
- `Download` отдаёт JSON через browser download;
- `Delete` требует подтверждение и удаляет выбранный файл;
- `Import config` читает локальный `.json`, проверяет JSON и записывает его в `/etc/sing-box`.

Когда именованный конфиг активен, внутренний `config.json` скрывается. Если именованный активный файл удалить, остаётся рабочая копия `config.json`.

`sing-box check` выполняется при сохранении/импорте, если ядро установлено. Если версия ядра не поддерживает операцию `check`, проверка считается необязательной; реальные ошибки показываются в уведомлении.

Лимиты rpcd/uhttpd обходятся через helper:

```text
запись > 52 КБ:  JS -> /tmp/.sbui-* текстовые фрагменты (16K символов) -> helper merge -> tmp -> mv -> destination
чтение >= 256 КиБ: JS -> helper read-chunk <file> <offset> (до 64 КиБ, по границе UTF-8) -> склейка в JS
```

`file.read` в rpcd отклоняет файлы от 256 КиБ (статус 8), `file.exec` отдаёт около 250 КБ stdout. Фрагменты — обычный текст, а не base64: в busybox на OpenWrt applet `base64` может отсутствовать. Чтение кусками использует `ucode` (зависимость `luci-base`).

Не меняйте этот путь на shell-команду с пользовательским вводом.

## Шаблоны

`template.json` оставлен для совместимости и отображается как `default.json`. Пользовательские шаблоны лежат в `/etc/singbox-ui/templates/*.json`.

Каждый шаблон можно создать, выбрать, отформатировать, сохранить или удалить. `default.json` удалять нельзя. Выбранное имя сохраняется в `active-template`.

Генератор сохраняет DNS, routes, inbounds и дополнительные outbounds, удаляет outbound с тегом `proxy` и вставляет туда outbound из share-ссылки. Поэтому шаблон отвечает за общую политику маршрутизации, а ссылка — только за основной proxy outbound.

Подсветка JSON визуальная, а не полноценный LSP. Реальное значение всегда находится в `textarea`, поэтому сохранение и копирование не зависят от overlay. При изменении редактора синхронно проверяйте пары:

```text
#editor + #editorHighlight
#templateEditor + #templateEditorHighlight
```

## Share-link parser

Контракт `share-link.js`:

```js
{ name: 'host-or-label', outbound: { type: '...', tag: 'proxy', ... } }
```

Поддерживаются VLESS, VMess, Trojan, Shadowsocks, Hysteria, Hysteria2/Hy2, TUIC, SOCKS и HTTP(S). Публичный API — `shareLink.parseShareLink()`; внутренние `parseVless`, `parseVmess` и остальные функции можно менять при сохранении результата.

Новый протокол добавляется вместе с тестом в `tests/share-link.test.js`. Реальные ссылки и секреты в fixtures запрещены.

## Helper и ACL

`singbox-ui-helper` работает с `set -eu` и принимает только:

```text
ensure-dir
activate/apply <name>
merge <safe-prefix> <safe-destination>
read-chunk <safe-destination> <offset>
cleanup <safe-prefix>
```

Он отвергает `..`, `/` и обратные слеши в именах, а destinations (и файлы для `read-chunk`) ограничены `/etc/sing-box/*.json`, legacy-шаблоном, `/etc/singbox-ui/templates/*.json` и временными check-файлами.

При добавлении runtime-пути обновляйте `root/usr/share/rpcd/acl.d/luci-app-singbox-ui.json`. Не давайте UI общий root-доступ или произвольный `exec`; privileged shell-операции добавляются узкими командами helper.

## Установщики

`install.sh` скачивает `ui.sh`, затем запускает `install-singbox+singbox-ui.sh` из `$BRANCH`. Устройство получает скрипты из GitHub, а не обязательно из уже установленного пакета.

В combined-flow:

1. выбирается операция: install, delete или reinstall/update;
2. при обновлении конфиги `/etc/sing-box/*.json` сохраняются во временный backup;
3. для действий `Singbox` и `Singbox and singbox-ui` пользователь выбирает вариант ядра;
4. запускаются дочерние скрипты;
5. backup конфигов восстанавливается после обновления.

Варианты ядра:

```text
1 Original — SagerNet/sing-box
2 Extended — shtorm-7/sing-box-extended
3 Clean — mrvokintos/sing-box-clean (Origin Clean / Extended Clean)
```

Выбор передаётся в `install-singbox.sh` через `SINGBOX_INSTALL_MODE`. Нельзя возвращать скрытый default Original в combined-flow.

`install-singbox.sh` определяет архитектуру из `/etc/openwrt_release`, `/etc/apk/arch` или `opkg print-architecture`, затем выбирает `.apk`/`.ipk` и GitHub asset с совпадающей OpenWrt-архитектурой. Extended и Extended Clean используют пакет `sing-box-extended` и конфликтуют с Original / Origin Clean `sing-box`.

`install-singbox-ui.sh` предлагает Latest, Pre-release и Runner PR. Latest ищет стабильный release, Pre-release — prerelease текущей ветки, Runner — тестовый пакет pull request. Размеры в меню приблизительные; текущие RC-пакеты около 15 КБ.

## Сборка и релизы

Пакеты собираются в официальном образе OpenWrt SDK ([`openwrt/sdk`](https://hub.docker.com/r/openwrt/sdk)). Версия SDK задаётся аргументом `SDK_TAG`: SDK 24.10 собирает `.ipk`, SDK 25.12 — `.apk`. Пакет `noarch`, поэтому хватает x86-64 SDK. Готовые файлы выгружаются из стадии `artifact` в каталог:

```sh
docker build --build-arg SDK_TAG=x86-64-24.10.8 --output type=local,dest=./bin-ipk .
docker build --build-arg SDK_TAG=x86-64-25.12.6 --output type=local,dest=./bin-apk .
```

Внутри Dockerfile подключается только фид `luci` (там `luci.mk` и host-утилиты jsmin/po2lmo/csstidy), затем:

```sh
make package/feeds/luci/luci-base/host/compile package/feeds/luci/csstidy/host/compile
make package/luci-app-singbox-ui/compile NO_DEPS=1 V=s
```

`NO_DEPS=1` нужен, потому что целевые зависимости `luci-base` (ucode, rpcd и т.д.) находятся в других фидах и для noarch-пакета не нужны. `/builder` в образе SDK объявлен как `VOLUME`, поэтому пакеты забираются через `--output`, а не через `docker cp`.

Пакеты из SDK не подписаны: подпись и индексы (`APKINDEX`, `Packages.sig`) добавляет `openwrt-repo` своим ключом. При ручной установке apk-пакета нужен `--allow-untrusted`.

Для автосборок `PKG_RELEASE` подменяется на UTC-метку `YYYYmmddHHMM`: apk допускает в релизе только целое число (`-rN`), а хеш коммита попадает в имя файла артефакта.

Release workflow (`build_luci-app-singbox-ui_from_tag.yml`) запускается вручную через `workflow_dispatch` с выбором версии тега и типа релиза (`prerelease` или `release`). Он извлекает версию без `v`, синхронизирует Makefile, собирает IPK и APK, а затем публикует оба файла в GitHub Release с выбранным флагом.

Автосборка после каждого коммита в ветках `main` и `dev` или PR (`build_luci-app-singbox-ui_from_pr.yml`) собирает пакеты и сохраняет их в артефактах GitHub Actions, а также в соответствующих каталогах отдельной ветки `artifacts` (`main/ipk`, `main/apk`, `dev/ipk`, `dev/apk`) для runner-установщика, не создавая GitHub Release.

### Форк

Адреса заданы в двух местах: `GITHUB_REPO` в `install.sh` и `luci-app-singbox-ui/root/usr/share/singbox-ui/setup/source.sh` (`SBUI_GITHUB_REPO`, `SBUI_CORE_REPO`, `REPO_BASE`, `ARTIFACTS_URL`). Их же можно задать переменными окружения при запуске, без правки кода:

```sh
SBUI_GITHUB_REPO=user/luci-app-singbox-ui sh install.sh
```

Проверка сети после настройки идёт по HTTP, а не ping, и при неудаче только предупреждает. Её можно отключить (`NETWORK_CHECK=0`) или задать свои адреса (`NETWORK_CHECK_URLS="http://..."`).

### Версии

Нумерация начата заново с `1.0.0`: версии `3.x` достались от исходного проекта (форка).

Единственный источник версии — `PKG_VERSION` в `luci-app-singbox-ui/Makefile`. `UI_VERSION` в `singbox-ui.js` должен совпадать с ним, это проверяет `tests/version.test.sh`. При сборке `Dockerfile` записывает в JS полную версию пакета: у релиза `1.0.0_rc1`, у автосборки `1.0.0_rc1-r202611041240`.

Тег пишется через дефис, версия пакета — через подчёркивание (apk не принимает `-` в версии). Release workflow сам переводит тег в версию пакета, одинаковую для APK и IPK:

```text
v1.0.0-rc1   ->  1.0.0_rc1
v1.2.0-rc.2  ->  1.2.0_rc2
v1.0.0       ->  1.0.0
```

Workflow записывает версию в Makefile и JS, ставит `PKG_RELEASE:=1` и коммитит это в выбранную ветку. Автосборки (`build_luci-app-singbox-ui_from_pr.yml`) оставляют `PKG_VERSION`, а в `PKG_RELEASE` пишут UTC-метку `YYYYmmddHHMM`: так каждая следующая сборка новее предыдущей.

### Политика версий

- опубликованные теги не переписывать;
- RC повышать последовательно (`rc1`, затем `rc2`);
- stable создавать только после явной команды пользователя;
- если тег собрался с ошибкой, исправление выпускается следующим RC.

## Проверки перед commit/tag

```sh
sh -n install.sh other/scripts/*.sh \\
  luci-app-singbox-ui/root/usr/sbin/singbox-ui \\
  luci-app-singbox-ui/root/usr/share/singbox-ui/setup/*.sh \\
  luci-app-singbox-ui/root/usr/libexec/singbox-ui-*
node --check luci-app-singbox-ui/htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js
node --check luci-app-singbox-ui/htdocs/luci-static/resources/singbox-ui/share-link.js
node tests/share-link.test.js
node tests/version-parser.test.js
sh tests/helper.test.sh
sh tests/setup.test.sh
sh tests/version.test.sh
jq empty luci-app-singbox-ui/root/usr/share/rpcd/acl.d/luci-app-singbox-ui.json
jq -e '.route.default_domain_resolver == "local-dns"' \\
  luci-app-singbox-ui/root/etc/singbox-ui/template.json
git diff --check
```

`tests/helper.test.sh` проверяет создание каталогов, merge config/template, сохранность файла при сбое merge, `read-chunk` (если есть `ucode`) и отклонение пути с `..`. Перед публикацией проверьте:

```sh
git status --short --branch
git ls-remote origin refs/heads/main
git ls-remote --tags origin
```

## Точки расширения

### Новая кнопка в списке конфигов

1. Добавьте ключ в `RU`.
2. Добавьте HTML-кнопку в `renderConfigs()`.
3. Добавьте обработчик в `init()`.
4. Для файловой операции проверьте `validName()`, ACL и helper.
5. Добавьте mobile CSS.

### Новое поле шаблона

Проверьте `saveTemplate`, format/reset, генератор и default template. Поле не должно очищаться при замене proxy outbound и не должно содержать секреты.

### Новый core fork или package format

Обновляйте сообщения обоих языков, выбор режима, asset lookup, package name/conflicts, `pkg.sh`, Dockerfile и workflow matrix. APK/IPK не следует считать взаимозаменяемыми.

## Ограничения и безопасность

- E2E-теста браузера сейчас нет; проверяются JS syntax, parser, pure-функции и helper.
- Подсветка JSON — визуальная, не полноценный LSP.
- Поведение `sing-box check` зависит от версии установленного ядра.
- Установщики требуют GitHub-доступ и `curl`/`wget`.
- Clean fork может не публиковать asset для каждой OpenWrt-архитектуры.
- Не коммитьте UUID, private key, password или реальные VLESS/Hysteria/SSH-ссылки.
- Не передавайте пользовательский текст в `sh -c`.
- Не расширяйте ACL до произвольного root-доступа.
- `/etc/sing-box/config.json` — рабочая копия сервиса; операции удаления и Apply должны учитывать active state.

## Происхождение и лицензия

Проект вырос из идеи `ang3el7z/luci-app-singbox-ui`, но актуальный fork и ссылки — `mrvokintos/luci-app-singbox-ui`. Лицензия и требования к производным изменениям находятся в `LICENSE` и `SECURITY.md`.
