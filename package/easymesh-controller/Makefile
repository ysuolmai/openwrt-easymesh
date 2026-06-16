include $(TOPDIR)/rules.mk

PKG_NAME:=easymesh-controller
PKG_RELEASE:=1

PKG_MAINTAINER:=ysuolmai
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/easymesh-controller
  SECTION:=net
  CATEGORY:=Network
  TITLE:=EasyMesh controller service
  DEPENDS:=+uhttpd +uhttpd-mod-ubus +libustream-openssl +jsonfilter +jshn +umdns
endef

define Package/easymesh-controller/description
  Minimal EasyMesh controller service for managing OpenWrt AP agents.
endef

define Package/easymesh-controller/conffiles
/etc/config/easymesh
endef

define Build/Compile
endef

define Package/easymesh-controller/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,easymesh-controller))
