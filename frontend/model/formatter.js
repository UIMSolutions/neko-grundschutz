sap.ui.define([
  "sap/ui/core/library"
], function (coreLibrary) {
  "use strict";

  var ValueState = coreLibrary.ValueState;

  return {
    /** Localised text of an enumeration value; must be called with a controller as `this`. */
    enumText: function (sValue) {
      if (sValue === null || sValue === undefined || sValue === "") {
        return "";
      }
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("enum." + sValue);
    },

    /** Text for frequency / impact scale values (1..4). */
    frequencyText: function (iValue) {
      return iValue ? this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("frequency." + iValue) : "";
    },

    impactText: function (iValue) {
      return iValue ? this.getOwnerComponent().getModel("i18n").getResourceBundle().getText("impact." + iValue) : "";
    },

    protectionState: function (sLevel) {
      switch (sLevel) {
        case "veryHigh": return ValueState.Error;
        case "high": return ValueState.Warning;
        case "normal": return ValueState.Success;
        default: return ValueState.None;
      }
    },

    riskState: function (sLevel) {
      switch (sLevel) {
        case "veryHigh": return ValueState.Error;
        case "high": return ValueState.Warning;
        case "medium": return ValueState.Information;
        case "low": return ValueState.Success;
        default: return ValueState.None;
      }
    },

    implementationState: function (sStatus) {
      switch (sStatus) {
        case "yes":
        case "dispensable": return ValueState.Success;
        case "partially": return ValueState.Warning;
        case "no": return ValueState.Error;
        default: return ValueState.None;
      }
    },

    projectState: function (sStatus) {
      switch (sStatus) {
        case "completed": return ValueState.Success;
        case "inProgress": return ValueState.Information;
        case "archived": return ValueState.None;
        default: return ValueState.Warning;
      }
    },

    /** "73 %" from a percentage number. */
    percent: function (fValue) {
      return (typeof fValue === "number" ? Math.round(fValue) : 0) + " %";
    },

    joinList: function (aValues) {
      return Array.isArray(aValues) && aValues.length ? aValues.join(", ") : "–";
    }
  };
});
