// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/settings.spec.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode face configures no locales, so
// its Settings page has no language selector: the labels are checked in English, and
// the identity is the chart's guest mapping to user:default/admin and group admins.
import { expect } from "@playwright/test";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { test } from "../support/fixtures";

let uiHelper: UIhelper;

test.describe(`Settings page`, () => {
  test.beforeEach(async ({ guestPage }) => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
    uiHelper = new UIhelper(guestPage);
    await uiHelper.openSidebar("Settings");
  });

  test(`Verify settings page`, async ({ guestPage }) => {
    await uiHelper.dismissQuickstartIfVisible();
    for (const label of ["Profile", "Appearance", "Theme", "Backstage Identity", "Pin Sidebar"]) {
      await uiHelper.verifyText(label);
    }
    await uiHelper.verifyText("Prevent the sidebar from collapsing");
    await uiHelper.verifyHeading("User Entity: admin");
    await uiHelper.verifyHeading("Ownership Entities: admins");

    await guestPage.getByTestId("user-settings-menu").click();
    await expect(guestPage.getByTestId("sign-out")).toContainText("Sign Out");
    await guestPage.keyboard.press("Escape");

    const sidebar = guestPage.getByRole("navigation", { name: "sidebar nav" });
    await uiHelper.uncheckCheckbox("Pin Sidebar Switch");
    await expect(sidebar.getByText("APIs", { exact: true })).toBeHidden();
    await uiHelper.checkCheckbox("Pin Sidebar Switch");
    await uiHelper.verifyText("Home");
  });
});
