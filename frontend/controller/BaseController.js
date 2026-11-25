sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/ui/core/routing/History",
  "sap/m/MessageToast",
  "sap/m/MessageBox",
  "uim/grundschutz/model/formatter"
], function (Controller, History, MessageToast, MessageBox, formatter) {
  "use strict";

  return Controller.extend("uim.grundschutz.controller.BaseController", {
    formatter: formatter,

    getRouter: function () {
      return this.getOwnerComponent().getRouter();
    },

    getModel: function (sName) {
      return this.getView().getModel(sName) || this.getOwnerComponent().getModel(sName);
    },

    getText: function (sKey, aArgs) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
    },

    toast: function (sKey, aArgs) {
      MessageToast.show(this.getText(sKey, aArgs));
    },

    /** Shows the backend error message (OData error payload) of a failed request. */
    showError: function (oError) {
      var sMessage = (oError && (oError.error && oError.error.message)) || (oError && oError.message) || String(oError);
      MessageBox.error(sMessage);
    },

    /** Creates an entity in a list binding and resolves with the created context. */
    createIn: function (oListBinding, oData) {
      var oContext = oListBinding.create(oData, true);
      return oContext.created().then(function () {
        return oContext;
      }, function (oError) {
        if (!oError.canceled) {
          oContext.delete().catch(function () { /* transient context already gone */ });
        }
        throw oError;
      });
    },

    // ------------------------------------------------------------ files: download, upload, print

    /** Root of the backend (works locally under /ui and behind the approuter under /). */
    apiUrl: function (sPath) {
      return this.getOwnerComponent().getModel().getServiceUrl().replace(/odata\/v4\/grundschutz\/$/, "") + sPath;
    },

    /** Starts a file download (attachment) without leaving the app. */
    download: function (sPath) {
      var oLink = document.createElement("a");
      oLink.href = this.apiUrl(sPath);
      oLink.download = "";
      document.body.appendChild(oLink);
      oLink.click();
      oLink.remove();
    },

    openPrint: function (sProjectId) {
      window.open(this.apiUrl("web/projects/" + encodeURIComponent(sProjectId) + "/print?auto=1"), "_blank", "noopener");
    },

    /** Lets the user choose a local file; resolves with the File. */
    pickFile: function (sAccept) {
      return new Promise(function (resolve) {
        var oInput = document.createElement("input");
        oInput.type = "file";
        oInput.accept = sAccept || ".csv,.json";
        oInput.addEventListener("change", function () {
          if (oInput.files && oInput.files[0]) {
            resolve(oInput.files[0]);
          }
        });
        oInput.click();
      });
    },

    /** CSRF token of the approuter / backend (required for POST behind the approuter). */
    _fetchCsrfToken: function () {
      return fetch(this.getOwnerComponent().getModel().getServiceUrl(), {
        method: "HEAD", credentials: "same-origin", headers: { "X-CSRF-Token": "Fetch" }
      }).then(function (oResponse) {
        return oResponse.headers.get("X-CSRF-Token") || "";
      });
    },

    /** Uploads a file to the exchange API; resolves with the parsed JSON report. */
    uploadFile: function (sPath, oFile) {
      var sType = /\.csv$/i.test(oFile.name) ? "text/csv" : "application/json";
      return Promise.all([this._fetchCsrfToken(), oFile.text()]).then(function (aResults) {
        return fetch(this.apiUrl(sPath), {
          method: "POST",
          credentials: "same-origin",
          headers: { "Content-Type": sType + "; charset=utf-8", "X-CSRF-Token": aResults[0], Accept: "application/json" },
          body: aResults[1]
        });
      }.bind(this)).then(function (oResponse) {
        return oResponse.json().then(function (oBody) {
          if (oBody.error) {
            throw oBody;
          }
          return oBody;
        });
      });
    },

    /** Shows an ImportReport (success toast or error list). */
    showImportReport: function (oReport) {
      var sSummary = this.getText("importSummary", [oReport.total, oReport.created, oReport.updated, oReport.skipped, oReport.failed]);
      if (!oReport.failed) {
        MessageBox.success(sSummary);
        return true;
      }
      var sDetails = (oReport.issues || []).slice(0, 15).map(function (oIssue) {
        return "#" + oIssue.row + (oIssue.id ? " (" + oIssue.id + ")" : "") + ": " + oIssue.message;
      }).join("\n");
      MessageBox.error(this.getText("importFailed") + "\n\n" + sSummary, { details: sDetails });
      return false;
    },

    onNavBack: function () {
      if (History.getInstance().getPreviousHash() !== undefined) {
        window.history.go(-1);
      } else {
        this.getRouter().navTo("main", {}, undefined, true);
      }
    },

    onCloseDialog: function (sId) {
      this.byId(sId).close();
    }
  });
});
