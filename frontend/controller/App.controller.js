sap.ui.define([
  "uim/grundschutz/controller/BaseController"
], function (BaseController) {
  "use strict";

  return BaseController.extend("uim.grundschutz.controller.App", {
    onInit: function () {
      this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass());
    }
  });
});
