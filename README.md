# luci-app-singbox-ui

[Русский](./README.ru.md)

Web interface for managing Sing-Box on OpenWrt 23/24/25.

## Disclaimer
> This project is intended strictly for educational and research purposes.
> The author takes no responsibility for misuse, device damage, or any consequences.
> Use at your own risk.

## Screenshot
<img width="972" height="858" alt="luci-app-singbox-ui screenshot" src="https://github.com/user-attachments/assets/198efa7a-6861-4f5f-9685-c717f3bb82a1" />

## Features
- Start, stop, and restart Sing-Box
- Discover every JSON config in /etc/sing-box/
- Apply or edit configs from a compact list
- Generate configs from VLESS, VMess, Trojan, Shadowsocks, Hysteria(2), TUIC, SOCKS and HTTP links
- Build generated configs from an editable routing/DNS template
- Never overwrite configs in the background
- Check service state and validate configs with the separately installed sing-box binary

## Installation
```bash
wget -O /root/install.sh https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/install.sh && chmod 0755 /root/install.sh && BRANCH="main" sh /root/install.sh
```

After running script:
1. Choose mode (`Singbox-ui`, `Singbox`, or both)
2. Choose operation (`Install`, `Uninstall`, `Reinstall/Update`)

## Quick Tips
Clear old SSH key:
```bash
ssh-keygen -R 192.168.1.1
```

Connect to router:
```bash
ssh root@192.168.1.1
```

If LuCI page is not visible after install, do a hard refresh.

## Config Templates
- [openwrt-template](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template.json)
- [openwrt-template-tproxy](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template-tproxy.json)
- [Sing-Box Configuration](https://sing-box.sagernet.org/configuration/)

## Contributing
Issues and pull requests are welcome.

## License
GNU General Public License v2.0 (GPL-2.0-only). See [LICENSE](./LICENSE).

## Stargazers over time
[![Stargazers over time](https://starchart.cc/ang3el7z/luci-app-singbox-ui.svg?variant=adaptive)](https://starchart.cc/ang3el7z/luci-app-singbox-ui)
