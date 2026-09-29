// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/learning-path-page.spec.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode sidebar has no Learning Paths
// entry, so the spec opens the page by its route. The page reads its links through the
// /developer-hub proxy that values-oidc.yaml configures, as upstream's CI does.
import { expect } from "@playwright/test";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { runAccessibilityTests } from "../support/accessibility";
import { test } from "../support/fixtures";

test.describe("Learning Paths", () => {
  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
  });

  test("Verify that links in Learning Paths for Backstage opens in a new tab", async ({
    guestPage,
  }, testInfo) => {
    await guestPage.goto("/learning-paths");
    await new UIhelper(guestPage).verifyHeading("Learning Paths");

    const learningPathLinks = guestPage.getByRole("main").getByRole("link");
    await expect(learningPathLinks.first()).toBeVisible();
    for (const learningPathLink of await learningPathLinks.all()) {
      await expect(learningPathLink).toBeVisible();
      await expect(learningPathLink).toHaveAttribute("target", "_blank");
      await expect(learningPathLink).not.toHaveAttribute("href", "");
    }

    await runAccessibilityTests(guestPage, testInfo);
  });
});
