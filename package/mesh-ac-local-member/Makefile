include $(TOPDIR)/rules.mk

PKG_NAME:=mesh-ac-local-member
PKG_RELEASE:=1

PKG_MAINTAINER:=ysuolmai
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/mesh-ac-local-member
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mesh AC local member support
  DEPENDS:=+mesh-ac +mesh-agent +jshn
endef

define Package/mesh-ac-local-member/description
  Optional local Wi-Fi mesh member support for mesh-ac controllers.
endef

define Build/Compile
endef

define Package/mesh-ac-local-member/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,mesh-ac-local-member))
