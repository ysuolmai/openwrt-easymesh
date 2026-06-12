include $(TOPDIR)/rules.mk

PKG_NAME:=mesh-ac
PKG_RELEASE:=1

PKG_MAINTAINER:=ysuolmai
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/mesh-ac
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mesh AC controller service
  DEPENDS:=+uhttpd +uhttpd-mod-ubus +libustream-openssl +jsonfilter +curl
endef

define Package/mesh-ac/description
  Minimal AC service for managing OpenWrt mesh AP agents.
endef

define Package/mesh-ac/conffiles
/etc/config/mesh_ac
/etc/mesh-ac/nodes.json
endef

define Build/Compile
endef

define Package/mesh-ac/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,mesh-ac))
