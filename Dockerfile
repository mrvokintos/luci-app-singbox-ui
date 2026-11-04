# Builds luci-app-singbox-ui with the official OpenWrt SDK image.
#   OpenWrt 25.12+ -> .apk   (SDK_TAG=x86-64-25.12.x)
#   OpenWrt 24.10  -> .ipk   (SDK_TAG=x86-64-24.10.x)
# The package is noarch, so the x86-64 SDK is enough for every target.
ARG SDK_TAG=x86-64-25.12.6
FROM docker.io/openwrt/sdk:${SDK_TAG} AS build

# Only the luci feed is needed: it provides luci.mk and the host tools
# (jsmin, po2lmo, csstidy). Target dependencies of luci-base (ucode, rpcd, ...)
# live in other feeds and are not needed to package a noarch LuCI app.
# The feed is taken from the official GitHub mirror at the commit pinned by
# this SDK release. `scripts/feeds update` exits 0 even when the clone fails,
# so success is checked explicitly and the clone is retried.
RUN sed -n 's#^src-git luci https://git.openwrt.org/project/luci.git#src-git luci https://github.com/openwrt/luci.git#p' \
      feeds.conf.default > feeds.conf \
 && grep -q '^src-git luci https://github.com/openwrt/luci.git^' feeds.conf \
 && for try in 1 2 3 4 5; do \
      rm -rf feeds/luci feeds/luci.*; \
      ./scripts/feeds update luci && [ -f feeds/luci/luci.mk ] && break; \
      [ "$try" = 5 ] && { echo "Failed to fetch the luci feed" >&2; exit 1; }; \
      sleep $((try * 10)); \
    done \
 && ./scripts/feeds install luci-base csstidy \
 && make defconfig \
 && make package/feeds/luci/luci-base/host/compile package/feeds/luci/csstidy/host/compile -j"$(nproc)"

COPY --chown=buildbot:buildbot ./luci-app-singbox-ui /builder/package/feeds/luci/luci-app-singbox-ui

# Версия панели в JS берётся из Makefile: PKG_VERSION, а у автосборок ещё -rN.
# The panel version in JS comes from the Makefile: PKG_VERSION, plus -rN for CI builds.
RUN cd package/feeds/luci/luci-app-singbox-ui \
 && v=$(sed -n 's/^PKG_VERSION:=//p' Makefile) \
 && r=$(sed -n 's/^PKG_RELEASE:=//p' Makefile) \
 && { [ "$r" = 1 ] || v="$v-r$r"; } \
 && sed -i "s/^const UI_VERSION='[^']*'/const UI_VERSION='$v'/" htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js \
 && grep -q "^const UI_VERSION='$v'" htdocs/luci-static/resources/view/singbox-ui/singbox-ui.js

RUN make defconfig \
 && make package/luci-app-singbox-ui/compile NO_DEPS=1 V=s \
 && mkdir -p /tmp/out \
 && cp bin/packages/*/luci/luci-app-singbox-ui* /tmp/out/ \
 && ls -l /tmp/out

# /builder is declared as a VOLUME in the SDK image, so packages are exported
# from a separate stage instead: docker build --output type=local,dest=DIR .
FROM scratch AS artifact
COPY --from=build /tmp/out/ /
