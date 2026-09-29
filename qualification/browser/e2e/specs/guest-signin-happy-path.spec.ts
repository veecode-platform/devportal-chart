// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/guest-signin-happy-path.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode home carries the search in its
// header, a "Your Starred Entities" card and a Toolkit card where RHDH's has a search
// widget, "Starred Catalog Entities" and Quick Access, and the chart signs the guest in
// as user:default/admin.
import { expect } from "@playwright/test";
import { LoginHelper, UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { test } from "../support/fixtures";

test.describe("Guest Signing Happy path", () => {
  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "authentication",
    });
  });

  let uiHelper: UIhelper;
  let loginHelper: LoginHelper;

  test.beforeEach(({ guestPage }) => {
    uiHelper = new UIhelper(guestPage);
    loginHelper = new LoginHelper(guestPage);
  });

  test("Verify the Homepage renders with Welcome heading, Search and Starred Entities", async ({
    guestPage,
  }) => {
    await uiHelper.verifyHeading(/^Welcome back/);
    await expect(guestPage.getByRole("combobox", { name: "Search..." })).toBeVisible();
    await uiHelper.verifyTextinCard("Your Starred Entities", "Your Starred Entities");
  });

  test("Verify the Homepage renders with the Toolkit", async () => {
    await uiHelper.verifyHeading(/^Welcome back/);
    await uiHelper.openSidebar("Home");
    await uiHelper.verifyLinkinCard("Toolkit", "Docs");
  });

  test("Verify the guest is the admin user in the Settings page", async () => {
    await uiHelper.openSidebar("Settings");
    await uiHelper.verifyHeading("User Entity: admin");
    await uiHelper.verifyHeading("Ownership Entities: admins");
  });

  test("Sign Out and Verify that you return to the Sign-in page", async () => {
    await uiHelper.openSidebar("Settings");
    await loginHelper.signOut();
  });
});
