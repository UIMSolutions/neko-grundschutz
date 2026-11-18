/* global QUnit */
sap.ui.define([
  "uim/grundschutz/model/formatter",
  "sap/ui/core/library"
], function (formatter, coreLibrary) {
  "use strict";

  var ValueState = coreLibrary.ValueState;

  QUnit.module("formatter");

  QUnit.test("protectionState", function (assert) {
    assert.strictEqual(formatter.protectionState("normal"), ValueState.Success);
    assert.strictEqual(formatter.protectionState("high"), ValueState.Warning);
    assert.strictEqual(formatter.protectionState("veryHigh"), ValueState.Error);
    assert.strictEqual(formatter.protectionState(undefined), ValueState.None);
  });

  QUnit.test("riskState", function (assert) {
    assert.strictEqual(formatter.riskState("low"), ValueState.Success);
    assert.strictEqual(formatter.riskState("veryHigh"), ValueState.Error);
  });

  QUnit.test("implementationState", function (assert) {
    assert.strictEqual(formatter.implementationState("yes"), ValueState.Success);
    assert.strictEqual(formatter.implementationState("dispensable"), ValueState.Success);
    assert.strictEqual(formatter.implementationState("no"), ValueState.Error);
    assert.strictEqual(formatter.implementationState("open"), ValueState.None);
  });

  QUnit.test("percent and joinList", function (assert) {
    assert.strictEqual(formatter.percent(72.6), "73 %");
    assert.strictEqual(formatter.percent(undefined), "0 %");
    assert.strictEqual(formatter.joinList(["A", "B"]), "A, B");
    assert.strictEqual(formatter.joinList([]), "–");
  });

  QUnit.test("enumText uses the i18n bundle of the controller", function (assert) {
    var oController = { getOwnerComponent: function () {
      return { getModel: function () { return { getResourceBundle: function () {
        return { getText: function (sKey) { return "T:" + sKey; } };
      } }; } };
    } };
    assert.strictEqual(formatter.enumText.call(oController, "veryHigh"), "T:enum.veryHigh");
    assert.strictEqual(formatter.enumText.call(oController, ""), "");
  });
});
