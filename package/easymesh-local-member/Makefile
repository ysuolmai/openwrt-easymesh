include $(TOPDIR)/rules.mk

PKG_NAME:=easymesh-local-member
PKG_RELEASE:=1

PKG_MAINTAINER:=ysuolmai
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/easymesh-local-member
  SECTION:=net
  CATEGORY:=Network
  TITLE:=EasyMesh local member support
  DEPENDS:=+easymesh-controller +easymesh-agent +jshn
endef

define Package/easymesh-local-member/description
  Optional local Wi-Fi mesh member support for easymesh-controller controllers.
endef

define Build/Compile
endef

define Package/easymesh-local-member/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,easymesh-local-member))
