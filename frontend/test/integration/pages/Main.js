sap.ui.define([
  "sap/ui/test/Opa5",
  "sap/ui/test/actions/Press"
], function (Opa5, Press) {
  "use strict";

  Opa5.createPageObjects({
    onTheMainPage: {
      viewName: "Main",
      actions: {
        iPressCreateProject: function () {
          return this.waitFor({ id: "createProjectButton", actions: new Press(), errorMessage: "Create button not found" });
        }
      },
      assertions: {
        iSeeTheProjectTable: function () {
          return this.waitFor({
            id: "projectTable",
            success: function () { Opa5.assert.ok(true, "Project table is displayed"); },
            errorMessage: "Project table not found"
          });
        },
        iSeeTheCreateDialog: function () {
          return this.waitFor({
            id: "createProjectDialog",
            success: function (oDialog) { Opa5.assert.ok(oDialog.isOpen(), "Create dialog is open"); },
            errorMessage: "Create dialog not found"
          });
        }
      }
    }
  });
});
