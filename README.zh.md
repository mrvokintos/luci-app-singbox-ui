# luci-app-singbox-ui

[English](./README.md) | [Русский](./README.ru.md)

用于在 OpenWrt 23/24/25 上管理 Sing-Box 的 Web 界面。

## 免责声明
> 本项目仅用于教育和研究目的。
> 作者不对误用、设备损坏或任何后果承担责任。
> 请自行承担使用风险。

## 截图
<img width="972" height="858" alt="luci-app-singbox-ui 截图" src="https://github.com/user-attachments/assets/198efa7a-6861-4f5f-9685-c717f3bb82a1" />

## 功能
- 启动、停止、重启 Sing-Box
- 通过 URL 或手动 JSON 添加订阅
- 在浏览器中保存并编辑多个配置
- 自动更新 Sing-Box 服务
- 检查服务与核心状态
- 内存不足时自动重启

## 安装
```bash
wget -O /root/install.sh https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/install.sh && chmod 0755 /root/install.sh && BRANCH="main" sh /root/install.sh
```

运行脚本后：
1. 选择模式（`Singbox-ui`、`Singbox` 或两者）
2. 选择操作（`Install`、`Uninstall`、`Reinstall/Update`）

## 快速提示
清理旧 SSH 指纹：
```bash
ssh-keygen -R 192.168.1.1
```

连接路由器：
```bash
ssh root@192.168.1.1
```

如果安装后 LuCI 页面没有显示，请强制刷新浏览器页面。

## 配置模板
- [openwrt-template](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template.json)
- [openwrt-template-tproxy](https://raw.githubusercontent.com/ang3el7z/luci-app-singbox-ui/main/other/file/openwrt-template-tproxy.json)
- [Sing-Box Configuration](https://sing-box.sagernet.org/configuration/)

## 贡献
欢迎提交 Issue 和 Pull Request。

## 许可证
GNU General Public License v2.0 (GPL-2.0-only)。见 [LICENSE](./LICENSE)。

## Stargazers over time
[![Stargazers over time](https://starchart.cc/ang3el7z/luci-app-singbox-ui.svg?variant=adaptive)](https://starchart.cc/ang3el7z/luci-app-singbox-ui)
