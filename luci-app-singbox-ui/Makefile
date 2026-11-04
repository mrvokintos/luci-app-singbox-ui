include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-singbox-ui
PKG_VERSION:=1.0.0_rc1
PKG_RELEASE:=1

LUCI_TITLE:=LuCI singbox-ui app
LUCI_DEPENDS:=+luci-base +ucode +ucode-mod-fs
LUCI_PKGARCH:=all
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=mrvokintos <mrvokintos@users.noreply.github.com>

define Package/luci-app-singbox-ui/conffiles
/etc/singbox-ui/template.json
/etc/config/singbox-ui
endef

# То же, что postinst из luci.mk, плюс подсказка про первоначальную настройку.
# Same as the luci.mk postinst, plus a hint about the initial setup.
define Package/luci-app-singbox-ui/postinst
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	[ "$${PKG_UPGRADE:-0}" = 1 ] || {
		echo "singbox-ui: run 'singbox-ui' over ssh for the initial setup (core, service, TUN, auto-update)."
		echo "singbox-ui: для первоначальной настройки выполните по ssh: singbox-ui"
	}
	exit 0
}
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
