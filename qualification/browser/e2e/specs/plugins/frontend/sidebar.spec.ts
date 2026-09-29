// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/plugins/frontend/sidebar.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode sidebar has no Learning Paths
// entry; its own entries, Tech Radar and Marketplace, take that case. The Docs entity case
// is left out because a fresh install has no TechDocs entity.
import { expect } from "@playwright/test";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { test } from "../../../support/fixtures";

test.describe("Validate Sidebar Navigation Customization", () => {
  let uiHelper: UIhelper;

  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "plugins",
    });
  });

  test.beforeEach(({ guestPage }) => {
    uiHelper = new UIhelper(guestPage);
  });

  test("Verify Docs sidebar navigation", async ({ guestPage }) => {
    await uiHelper.openSidebar("Docs");

    await expect(guestPage).toHaveURL(/\/docs(\?|$)/u);
    await uiHelper.verifyHeading("Documentation");
  });

  test("Verify Tech Radar sidebar navigation", async ({ guestPage }) => {
    await uiHelper.openSidebar("Tech Radar");

    await expect(guestPage).toHaveURL(/\/tech-radar(\?|$)/u);
    await uiHelper.verifyHeading("Tech Radar");
  });

  test("Verify Marketplace sidebar navigation", async ({ guestPage }) => {
    await guestPage
      .getByRole("navigation", { name: "sidebar nav" })
      .getByRole("link", { name: "Marketplace" })
      .click();

    await expect(guestPage).toHaveURL(/\/marketplace/u);
  });
});
