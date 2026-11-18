sap.ui.define([
  "sap/ui/model/json/JSONModel",
  "sap/ui/Device"
], function (JSONModel, Device) {
  "use strict";

  function keys(aValues) {
    return aValues.map(function (s) { return { key: s }; });
  }

  return {
    createDeviceModel: function () {
      var oModel = new JSONModel(Device);
      oModel.setDefaultBindingMode("OneWay");
      return oModel;
    },

    /** Value lists of the backend enumerations (texts come from i18n "enum.<key>"). */
    createEnumModel: function () {
      var oModel = new JSONModel({
        approaches: keys(["basic", "standard", "core"]),
        projectStatuses: keys(["planned", "inProgress", "completed", "archived"]),
        protectionLevels: keys(["normal", "high", "veryHigh"]),
        objectKinds: keys(["businessProcess", "application", "itSystem", "icsSystem", "iotSystem",
          "room", "building", "network", "communicationLink"]),
        implementationStatuses: keys(["open", "yes", "partially", "no", "dispensable"]),
        requirementLevels: keys(["basic", "standard", "elevated"]),
        treatments: keys(["open", "avoid", "reduce", "transfer", "accept"]),
        scale: [1, 2, 3, 4].map(function (i) { return { key: i }; })
      });
      oModel.setDefaultBindingMode("OneWay");
      return oModel;
    }
  };
});
