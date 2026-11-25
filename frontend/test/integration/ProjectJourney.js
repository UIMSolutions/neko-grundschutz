/* global QUnit */
sap.ui.define([
  "sap/ui/test/opaQunit",
  "sap/ui/test/Opa5",
  "uim/grundschutz/test/integration/pages/Main"
], function (opaTest, Opa5) {
  "use strict";

  Opa5.extendConfig({ viewNamespace: "uim.grundschutz.view.", autoWait: true });

  QUnit.module("Projects");

  opaTest("shows the project list and opens the create dialog", function (Given, When, Then) {
    Given.iStartMyUIComponent({ componentConfig: { name: "uim.grundschutz", async: true } });
    Then.onTheMainPage.iSeeTheProjectTable();
    When.onTheMainPage.iPressCreateProject();
    Then.onTheMainPage.iSeeTheCreateDialog();
    Then.iTeardownMyUIComponent();
  });
});
