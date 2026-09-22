include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-singbox-ui
PKG_VERSION:=3.0.0_rc1
PKG_RELEASE:=1

LUCI_TITLE:=LuCI singbox-ui app
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=mrvokintos <mrvokintos@users.noreply.github.com>

define Package/luci-app-singbox-ui/conffiles
/etc/singbox-ui/template.json
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
