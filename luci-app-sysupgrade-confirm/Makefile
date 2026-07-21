# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2026 Chip Schweiss
#
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sysupgrade-confirm
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Chip Schweiss <chip@innovates.com>
PKG_LICENSE:=GPL-2.0-or-later

LUCI_TITLE:=LuCI page for sysupgrade-confirm
LUCI_DEPENDS:=+sysupgrade-confirm +luci-base
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
