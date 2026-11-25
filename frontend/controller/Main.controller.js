sap.ui.define([
  "uim/grundschutz/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/m/MessageBox"
], function (BaseController, JSONModel, Filter, FilterOperator, MessageBox) {
  "use strict";

  function emptyProject() {
    return { name: "", scope: "", description: "", owner: "", approach: "standard" };
  }

  return BaseController.extend("uim.grundschutz.controller.Main", {
    onInit: function () {
      this.getView().setModel(new JSONModel(emptyProject()), "newProject");
    },

    onSearch: function (oEvent) {
      var sQuery = oEvent.getParameter("newValue") !== undefined ? oEvent.getParameter("newValue") : oEvent.getParameter("query");
      var aFilters = sQuery ? [new Filter({ path: "name", operator: FilterOperator.Contains, value1: sQuery, caseSensitive: false })] : [];
      this.byId("projectTable").getBinding("items").filter(aFilters);
    },

    onRefresh: function () {
      this.byId("projectTable").getBinding("items").refresh();
    },

    onProjectPress: function (oEvent) {
      var oContext = oEvent.getSource().getBindingContext();
      this.getRouter().navTo("project", { projectId: encodeURIComponent(oContext.getProperty("ID")) });
    },

    onOpenWebGui: function () {
      window.open(this.apiUrl("web"), "_blank", "noopener");
    },

    onOpenAdmin: function () {
      window.open(this.apiUrl("web/admin"), "_blank", "noopener");
    },

    onExportProjects: function (sFormat) {
      this.download("api/export/projects?format=" + sFormat);
    },

    onDownloadBackup: function () {
      this.download("api/backup");
    },

    /** Imports a project file (export of a project); asks whether to create a copy. */
    onImportProject: function () {
      this.pickFile(".json").then(function (oFile) {
        MessageBox.confirm(this.getText("importAsCopy"), {
          actions: [MessageBox.Action.YES, MessageBox.Action.NO, MessageBox.Action.CANCEL],
          emphasizedAction: MessageBox.Action.NO,
          onClose: function (sAction) {
            if (sAction === MessageBox.Action.CANCEL) {
              return;
            }
            this.uploadFile("api/projects/import?newIds=" + (sAction === MessageBox.Action.YES), oFile)
              .then(function (oReport) {
                if (this.showImportReport(oReport)) {
                  this.onRefresh();
                }
              }.bind(this), this.showError.bind(this));
          }.bind(this)
        });
      }.bind(this));
    },

    onOpenCreateDialog: function () {
      this.getView().getModel("newProject").setData(emptyProject());
      this.byId("createProjectDialog").open();
    },

    onCloseCreateDialog: function () {
      this.byId("createProjectDialog").close();
    },

    onCreateProject: function () {
      var oData = this.getView().getModel("newProject").getData();
      var oDialog = this.byId("createProjectDialog");
      oDialog.setBusy(true);
      this.createIn(this.byId("projectTable").getBinding("items"), Object.assign({}, oData)).then(function (oContext) {
        oDialog.close();
        this.toast("created");
        this.getRouter().navTo("project", { projectId: encodeURIComponent(oContext.getProperty("ID")) });
      }.bind(this), this.showError.bind(this)).finally(function () {
        oDialog.setBusy(false);
      });
    }
  });
});
