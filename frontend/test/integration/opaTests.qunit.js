/* global QUnit */
QUnit.config.autostart = false;

sap.ui.getCore().attachInit(function () {
  "use strict";
  sap.ui.require(["uim/grundschutz/test/integration/ProjectJourney"], function () {
    QUnit.start();
  });
});
