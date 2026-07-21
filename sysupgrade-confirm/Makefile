# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2026 Chip Schweiss
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_NAME:=sysupgrade-confirm
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Chip Schweiss <chip@innovates.com>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/sysupgrade-confirm
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Confirmed sysupgrade for dual-firmware devices
  URL:=https://github.com/lschweiss/sysupgrade-confirm
  DEPENDS:=+uboot-envtools +jsonfilter +rpcd
  PKGARCH:=all
endef

define Package/sysupgrade-confirm/description
 Arm-before-flash / confirm-after-boot guard for dual-firmware OpenWrt
 devices (Linksys MX5300/MX8500 first). If the new firmware boots but is
 not confirmed (CLI, token'd ubus call, or optional auto-checks) within a
 monotonic deadline, the boot partition is flipped back and the device
 reboots into the previous firmware. The stock bootloader boot-counter
 (layer 1) is left untouched; this is an independent second layer that
 catches "boots fine, network dead" failures the boot counter cannot see.
 Integrates with owut via its pre_install hook (run-parts dispatcher) and
 self-carries across flashes via /lib/upgrade/keep.d.
endef

define Package/sysupgrade-confirm/conffiles
/etc/config/sysupgrade-confirm
endef

define Build/Compile
endef

define Package/sysupgrade-confirm/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/sysupgrade-confirm.sh $(1)/usr/sbin/sysupgrade-confirm
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/sysupgrade-confirm.init $(1)/etc/init.d/sysupgrade-confirm
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/sysupgrade-confirm.config $(1)/etc/config/sysupgrade-confirm
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./files/sysupgrade-confirm.rpcd $(1)/usr/libexec/rpcd/sysupgrade-confirm
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/sysupgrade-confirm.acl.json $(1)/usr/share/rpcd/acl.d/sysupgrade-confirm.json
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/owut-pre-install-dispatch $(1)/usr/libexec/owut-pre-install-dispatch
	$(INSTALL_DIR) $(1)/etc/owut.d/pre-install.d
	$(INSTALL_BIN) ./files/50-sysupgrade-confirm.hook $(1)/etc/owut.d/pre-install.d/50-sysupgrade-confirm
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./files/60-sysupgrade-confirm-owut.defaults $(1)/etc/uci-defaults/60-sysupgrade-confirm-owut
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/sysupgrade-confirm.keep $(1)/lib/upgrade/keep.d/sysupgrade-confirm
	$(INSTALL_DIR) $(1)/usr/share/sysupgrade-confirm/boards
	$(INSTALL_DATA) ./files/boards/*.json $(1)/usr/share/sysupgrade-confirm/boards/
endef

$(eval $(call BuildPackage,sysupgrade-confirm))
