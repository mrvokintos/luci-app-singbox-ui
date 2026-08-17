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
| `other/scripts/install-singbox.sh` | Установка, обновление и удаление ядра |
| `other/scripts/install-singbox-ui.sh` | Установка, обновление и удаление UI |
| `other/scripts/install-singbox+singbox-ui.sh` | Комбинированный установщик |
| `other/scripts/lib/ui.sh` | Общие сообщения, ввод и прогресс |
| `other/scripts/lib/pkg.sh` | APK/IPK, архитектура и операции пакетов |
| `install.sh` | Bootstrap, скачивающий актуальные скрипты из `$BRANCH` |
| `Dockerfile-ipk`, `Dockerfile-apk` | OpenWrt SDK-сборки |
| `.github/workflows/build_luci-app-singbox-ui_from_tag.yml` | Ручная сборка и публикация GitHub Release (Release/Pre-release) |
| `.github/workflows/build_luci-app-singbox-ui_from_pr.yml` | Автосборка артефактов при коммите/PR |
| `tests/share-link.test.js` | Тесты parser |
| `tests/helper.test.sh` | Тесты helper и защиты путей |

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

Для файлов больше лимита LuCI используется схема:

```text
JS -> /tmp/.sbui-* fragments -> helper merge -> destination
```

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
cleanup <safe-prefix>
```

Он отвергает `..`, `/` и обратные слеши в именах, а destinations ограничены `/etc/sing-box/*.json`, legacy-шаблоном, `/etc/singbox-ui/templates/*.json` и временными check-файлами.

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
3 Clean — mrvokintos/sing-box-extended
```

Выбор передаётся в `install-singbox.sh` через `SINGBOX_INSTALL_MODE`. Нельзя возвращать скрытый default Original в combined-flow.

`install-singbox.sh` определяет архитектуру из `/etc/openwrt_release`, `/etc/apk/arch` или `opkg print-architecture`, затем выбирает `.apk`/`.ipk` и GitHub asset с совпадающей OpenWrt-архитектурой. Extended и Clean используют пакет `sing-box-extended` и конфликтуют с Original `sing-box`.

`install-singbox-ui.sh` предлагает Latest, Pre-release и Runner PR. Latest ищет стабильный release, Pre-release — prerelease текущей ветки, Runner — тестовый пакет pull request. Размеры в меню приблизительные; текущие RC-пакеты около 15 КБ.

## Сборка и релизы

Локальная SDK-сборка:

```sh
docker build -f Dockerfile-ipk -t singbox-ui-ipk:local .
docker build -f Dockerfile-apk -t singbox-ui-apk:local .
```

Внутри Dockerfile выполняется:

```sh
make defconfig
make package/luci-app-singbox-ui/compile V=s -j4
```

Release workflow (`build_luci-app-singbox-ui_from_tag.yml`) запускается вручную через `workflow_dispatch` с выбором версии тега и типа релиза (`prerelease` или `release`). Он извлекает версию без `v`, синхронизирует Makefile, собирает IPK и APK, а затем публикует оба файла в GitHub Release с выбранным флагом.

Автосборка после каждого коммита в ветках `main` и `dev` или PR (`build_luci-app-singbox-ui_from_pr.yml`) собирает пакеты и сохраняет их в артефактах GitHub Actions, а также в соответствующих каталогах отдельной ветки `artifacts` (`main/ipk`, `main/apk`, `dev/ipk`, `dev/apk`) для runner-установщика, не создавая GitHub Release.

### Tag version и APK version — это не одно и то же

Человекочитаемая версия остаётся такой:

```text
v3.1.0-rc5
UI 3.1.0-rc5
```

APK/Alpine принимает RC-суффикс в форме underscore, поэтому workflow преобразует только внутреннюю package version:

```text
3.1.0-rc4  ->  3.1.0_rc4
3.2.0-rc.1 ->  3.2.0_rc1
```

Не меняйте Git-тег ради APK. Эта ошибка уже приводила к падению APK jobs у `rc1`, `rc2` и `rc3`.

### Политика версий

- опубликованные теги не переписывать;
- RC повышать последовательно (`rc4`, затем `rc5`);
- stable создавать только после явной команды пользователя;
- если тег собрался с ошибкой, исправление выпускается следующим RC.

Текущее состояние: `v3.1.0-rc5` — prerelease с документацией для разработчиков; `v3.1.0-rc4` — последний успешно собранный пакет до этого изменения; `v3.1.0-rc3` — тег с неудачной APK-сборкой до исправления package-version normalization.

## Проверки перед commit/tag

```sh
sh -n install.sh other/scripts/*.sh other/scripts/lib/*.sh \\
  luci-app-singbox-ui/root/usr/libexec/singbox-ui-helper
node --check luci-app-singbox-ui/htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js
node --check luci-app-singbox-ui/htdocs/luci-static/resources/singbox-ui/share-link.js
node tests/share-link.test.js
node tests/version-parser.test.js
sh tests/helper.test.sh
jq empty luci-app-singbox-ui/root/usr/share/rpcd/acl.d/luci-app-singbox-ui.json
jq -e '.route.default_domain_resolver == "local-dns"' \\
  luci-app-singbox-ui/root/etc/singbox-ui/template.json
git diff --check
```

`tests/helper.test.sh` проверяет создание каталогов, merge config/template и отклонение пути с `..`. Перед публикацией проверьте:

```sh
git status --short --branch
git ls-remote origin refs/heads/main
git tag --list 'v3.1.0-rc*'
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
