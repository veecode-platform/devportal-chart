// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/home-page-customization.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode home is the veecode-homepage
// plugin: its cards are Summary, Recently Visited, Your Starred Entities, Top Visited and
// Toolkit, and the Toolkit links take the place of RHDH's Quick Access sections.
import { HomePage } from "@red-hat-developer-hub/e2e-test-utils/pages";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { runAccessibilityTests } from "../support/accessibility";
import { test } from "../support/fixtures";

test.describe("Home page customization", () => {
  let homePage: HomePage;
  let uiHelper: UIhelper;

  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
  });

  test.beforeEach(({ guestPage }) => {
    homePage = new HomePage(guestPage);
    uiHelper = new UIhelper(guestPage);
  });

  test("Verify that home page is customized", async ({ guestPage }, testInfo) => {
    await uiHelper.verifyTextinCard("Summary", "Resources");

    await runAccessibilityTests(guestPage, testInfo);

    await uiHelper.verifyTextinCard("Toolkit", "Toolkit");
    await uiHelper.verifyTextinCard("Your Starred Entities", "Your Starred Entities");
  });

  test("Verify that the Top Visited card in the Home page renders without an error", async () => {
    await uiHelper.verifyTextinCard("Top Visited", "Top Visited");
    await homePage.verifyVisitedCardContent("Top Visited");
  });

  test("Verify that the Recently Visited card in the Home page renders without an error", async () => {
    await uiHelper.verifyTextinCard("Recently Visited", "Recently Visited");
    await homePage.verifyVisitedCardContent("Recently Visited");
  });

  test("Verify the Toolkit links", async () => {
    for (const link of ["Docs", "Community", "Website", "Support"]) {
      await uiHelper.verifyLinkinCard("Toolkit", link);
    }
  });
});
