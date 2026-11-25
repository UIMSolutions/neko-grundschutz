sap.ui.define([
  "uim/grundschutz/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/m/MessageBox",
  "sap/m/MessagePopover",
  "sap/m/MessageItem"
], function (BaseController, JSONModel, Filter, FilterOperator, MessageBox, MessagePopover, MessageItem) {
  "use strict";

  function emptyObject() {
    return { name: "", kind: "itSystem", description: "", confidentiality: "normal", integrity: "normal",
      availability: "normal", protectionRationale: "" };
  }

  function emptyRisk() {
    return { targetObjectId: "", threatCode: "G 0.1", title: "", description: "", frequency: "1", impact: "1",
      treatment: "open", treatmentNote: "" };
  }

  /** OData string literal. */
  function literal(s) {
    return "'" + String(s).replace(/'/g, "''") + "'";
  }

  return BaseController.extend("uim.grundschutz.controller.Project", {
    onInit: function () {
      var oView = this.getView();
      oView.setModel(new JSONModel(emptyObject()), "newObject");
      oView.setModel(new JSONModel(emptyRisk()), "newRisk");
      oView.setModel(new JSONModel({}), "report");
      this.getRouter().getRoute("project").attachPatternMatched(this._onPatternMatched, this);
    },

    _onPatternMatched: function (oEvent) {
      this._sProjectId = decodeURIComponent(oEvent.getParameter("arguments").projectId);
      this.getView().bindElement({ path: "/Projects(" + literal(this._sProjectId) + ")" });
      this.byId("tabs").setSelectedKey("objects");
      this._loadReport();
    },

    onTabSelect: function (oEvent) {
      var sKey = oEvent.getParameter("key");
      if (sKey === "report") {
        this._loadReport();
      } else if (sKey === "requirements" || sKey === "risks") {
        this.byId(sKey === "risks" ? "riskTable" : "requirementTable").getBinding("items").refresh();
      }
    },

    onRefresh: function () {
      var oModel = this.getModel();
      try {
        oModel.resetChanges("$direct");
      } catch (e) { /* nothing pending */ }
      oModel.refresh();
      this._loadReport();
    },

    /** Loads the GetProjectReport function result into the "report" JSON model. */
    _loadReport: function () {
      var sUrl = this.getModel().getServiceUrl() + "GetProjectReport(projectId=" + encodeURIComponent(literal(this._sProjectId)) + ")";
      var oReport = this.getView().getModel("report");
      fetch(sUrl, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(function (r) { return r.ok ? r.json() : r.json().then(function (e) { throw e; }); })
        .then(function (oData) { oReport.setData(oData); })
        .catch(this.showError.bind(this));
    },

    // ------------------------------------------------------------------ target objects

    onOpenObjectDialog: function () {
      this.getView().getModel("newObject").setData(emptyObject());
      this.byId("objectDialog").open();
    },

    onCreateObject: function () {
      var oDialog = this.byId("objectDialog");
      var oData = Object.assign({}, this.getView().getModel("newObject").getData());
      oDialog.setBusy(true);
      this.createIn(this.byId("objectTable").getBinding("items"), oData).then(function () {
        oDialog.close();
        this.toast("created");
        this._loadReport();
      }.bind(this), this.showError.bind(this)).finally(function () {
        oDialog.setBusy(false);
      });
    },

    onApplyModule: function () {
      var oItem = this.byId("objectTable").getSelectedItem();
      if (!oItem) {
        MessageBox.information(this.getText("selectTargetObject"));
        return;
      }
      var sModule = this.byId("moduleSelect").getSelectedKey();
      var oAction = this.getModel().bindContext("/ApplyModule(...)");
      oAction.setParameter("targetObjectId", oItem.getBindingContext().getProperty("ID"));
      oAction.setParameter("moduleCode", sModule);
      oAction.execute().then(function () {
        var oResult = oAction.getBoundContext() && oAction.getBoundContext().getObject();
        var aCreated = Array.isArray(oResult) ? oResult : (oResult && oResult.value) || [];
        this.toast("modulesApplied", [aCreated.length]);
        this.byId("requirementTable").getBinding("items").refresh();
        this._loadReport();
      }.bind(this), this.showError.bind(this));
    },

    // ------------------------------------------------------------------ requirements

    onStatusFilter: function (oEvent) {
      var sKey = oEvent.getSource().getSelectedKey();
      this.byId("requirementTable").getBinding("items")
        .filter(sKey ? [new Filter("status", FilterOperator.EQ, sKey)] : []);
    },

    // ------------------------------------------------------------------ risks

    onOpenRiskDialog: function () {
      this.getView().getModel("newRisk").setData(emptyRisk());
      this.byId("riskDialog").open();
    },

    onCreateRisk: function () {
      var oDialog = this.byId("riskDialog");
      var oData = Object.assign({}, this.getView().getModel("newRisk").getData());
      oData.targetObjectId = oData.targetObjectId || this.byId("rdObj").getSelectedKey();
      oData.threatCode = oData.threatCode || this.byId("rdThreat").getSelectedKey();
      oData.frequency = parseInt(oData.frequency, 10);
      oData.impact = parseInt(oData.impact, 10);
      oDialog.setBusy(true);
      this.createIn(this.byId("riskTable").getBinding("items"), oData).then(function () {
        oDialog.close();
        this.toast("created");
        this._loadReport();
      }.bind(this), this.showError.bind(this)).finally(function () {
        oDialog.setBusy(false);
      });
    },

    // ------------------------------------------------------------------ deletion

    onDeleteSelected: function (sTableId) {
      var oItem = this.byId(sTableId).getSelectedItem();
      if (!oItem) {
        return;
      }
      var oContext = oItem.getBindingContext();
      var sName = oContext.getProperty("name") || oContext.getProperty("title");
      MessageBox.confirm(this.getText("deleteConfirm", [sName]), {
        onClose: function (sAction) {
          if (sAction !== MessageBox.Action.OK) {
            return;
          }
          oContext.delete().then(function () {
            this.toast("deleted");
            this.byId("requirementTable").getBinding("items").refresh();
            this._loadReport();
          }.bind(this), this.showError.bind(this));
        }.bind(this)
      });
    },

    onDeleteProject: function () {
      var oContext = this.getView().getBindingContext();
      MessageBox.confirm(this.getText("deleteConfirm", [oContext.getProperty("name")]), {
        emphasizedAction: MessageBox.Action.CANCEL,
        onClose: function (sAction) {
          if (sAction !== MessageBox.Action.OK) {
            return;
          }
          oContext.delete().then(function () {
            this.toast("deleted");
            this.getModel().refresh();
            this.getRouter().navTo("main", {}, undefined, true);
          }.bind(this), this.showError.bind(this));
        }.bind(this)
      });
    },

    // ------------------------------------------------------------------ print, export, import

    onPrint: function () {
      this.openPrint(this._sProjectId);
    },

    onExportProject: function () {
      this.download("api/projects/" + encodeURIComponent(this._sProjectId) + "/export");
    },

    onExportEntity: function (sEntity, sFormat) {
      this.download("api/export/" + sEntity + "?format=" + sFormat + "&projectId=" + encodeURIComponent(this._sProjectId));
    },

    /** Imports CSV/JSON rows into this project (new rows are created, existing ones updated). */
    onImportEntity: function (sEntity) {
      this.pickFile(".csv,.json").then(function (oFile) {
        var sPath = "api/import/" + sEntity + "?format=auto&mode=upsert&projectId=" + encodeURIComponent(this._sProjectId);
        this.getView().setBusy(true);
        this.uploadFile(sPath, oFile).then(function (oReport) {
          if (this.showImportReport(oReport)) {
            this.getModel().refresh();
            this._loadReport();
          }
        }.bind(this), this.showError.bind(this)).finally(function () {
          this.getView().setBusy(false);
        }.bind(this));
      }.bind(this));
    },

    // ------------------------------------------------------------------ messages

    onShowMessages: function (oEvent) {
      if (!this._oMessagePopover) {
        this._oMessagePopover = new MessagePopover({
          items: {
            path: "message>/",
            template: new MessageItem({ type: "{message>type}", title: "{message>message}", subtitle: "{message>target}" })
          }
        });
        this.getView().addDependent(this._oMessagePopover);
      }
      this._oMessagePopover.toggle(oEvent.getSource());
    }
  });
});
