# luci-app-singbox-ui

[English](./README.md)

Веб-интерфейс для управления Sing-Box на OpenWrt 23/24/25.

## Предупреждение
> Проект предназначен только для образовательных и исследовательских целей.
> Автор не несет ответственности за неправильное использование, поломку устройств и любые последствия.
> Использование на ваш страх и риск.

## Скриншот
<img width="972" height="858" alt="Скриншот luci-app-singbox-ui" src="https://github.com/user-attachments/assets/026aca3e-ba20-479a-b8bd-3e42344f9eff" />

## Возможности
- Запуск, остановка и перезапуск Sing-Box
- Автоматический поиск всех JSON-файлов в /etc/sing-box/
- Применение и редактирование конфигов из компактного списка
- Генерация конфигов из ссылок VLESS, VMess, Trojan, Shadowsocks, Hysteria(2), TUIC, SOCKS и HTTP
- Редактируемый шаблон с DNS, маршрутами и дополнительными outbound
- Никакой фоновой перезаписи конфигов
- Проверка состояния сервиса и конфигов через отдельно установленный бинарник sing-box

## Установка
```bash
wget -O /root/install.sh https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/install.sh && chmod 0755 /root/install.sh && BRANCH="main" sh /root/install.sh
```

После запуска скрипта:
1. Выберите режим (`Singbox-ui`, `Singbox` или оба сразу)
2. Выберите операцию (`Установка`, `Удаление`, `Переустановка/Обновление`)

## Быстрые подсказки
Очистить старый SSH-ключ:
```bash
ssh-keygen -R 192.168.1.1
```

Подключиться к роутеру:
```bash
ssh root@192.168.1.1
```

Если страница LuCI не появилась после установки, выполните жесткое обновление страницы в браузере.

## Шаблоны конфигурации
- [openwrt-template](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template.json)
- [openwrt-template-tproxy](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template-tproxy.json)
- [Sing-Box Configuration](https://sing-box.sagernet.org/configuration/)

## Вклад
Issues и pull request приветствуются.

## Лицензия
GNU General Public License v2.0 (GPL-2.0-only). См. [LICENSE](./LICENSE).

## Stargazers over time
[![Stargazers over time](https://starchart.cc/ang3el7z/luci-app-singbox-ui.svg?variant=adaptive)](https://starchart.cc/ang3el7z/luci-app-singbox-ui)
