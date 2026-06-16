include $(TOPDIR)/rules.mk

PKG_NAME:=easymesh-agent
PKG_RELEASE:=1

PKG_MAINTAINER:=ysuolmai
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/easymesh-agent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mesh managed AP agent
  DEPENDS:=+curl +jsonfilter +umdns +iw +ip-bridge +wpad-openssl +kmod-batman-adv +batctl-default +dawn
endef

define Package/easymesh-agent/description
  Managed AP agent for EasyMesh.
endef

define Package/easymesh-agent/conffiles
/etc/config/easymesh_agent
/etc/easymesh-agent/config.json
endef

define Build/Compile
endef

define Package/easymesh-agent/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,easymesh-agent))
