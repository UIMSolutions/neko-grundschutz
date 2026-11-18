sap.ui.define([
  "sap/ui/core/UIComponent",
  "sap/ui/core/Messaging",
  "uim/grundschutz/model/models"
], function (UIComponent, Messaging, models) {
  "use strict";

  return UIComponent.extend("uim.grundschutz.Component", {
    metadata: {
      manifest: "json",
      interfaces: ["sap.ui.core.IAsyncContentCreation"]
    },

    init: function () {
      UIComponent.prototype.init.apply(this, arguments);
      this.setModel(models.createDeviceModel(), "device");
      this.setModel(models.createEnumModel(), "enums");
      this.setModel(Messaging.getMessageModel(), "message");
      this.getRouter().initialize();
    },

    /** CSS class for content density (compact on desktop, cozy on touch devices). */
    getContentDensityClass: function () {
      if (this._sContentDensityClass === undefined) {
        this._sContentDensityClass = document.body.classList.contains("sapUiSizeCozy") ||
          !sap.ui.require("sap/ui/Device").support.touch ? "sapUiSizeCompact" : "sapUiSizeCozy";
      }
      return this._sContentDensityClass;
    }
  });
});
