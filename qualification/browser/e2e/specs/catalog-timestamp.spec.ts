// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/catalog-timestamp.spec.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b, on the library's UIhelper and
// CatalogImportPage. The VeeCode catalog opens on all Components, so no kind is picked.
import { expect, type Page } from "@playwright/test";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";
import { CatalogImportPage } from "@red-hat-developer-hub/e2e-test-utils/pages";

import { test } from "../support/fixtures";

async function firstRowCreatedAt(page: Page) {
  const headers = await page.getByRole("columnheader").allInnerTexts();
  const column = headers.findIndex((header) => header.trim() === "Created At");
  expect(column).toBeGreaterThanOrEqual(0);
  const firstRow = page.getByRole("row").filter({ has: page.getByRole("cell") }).first();
  return firstRow.getByRole("cell").nth(column);
}

test.describe("Test timestamp column on Catalog", () => {
  let uiHelper: UIhelper;
  let catalogImport: CatalogImportPage;

  const component =
    "https://github.com/janus-qe/custom-catalog-entities/blob/main/timestamp-catalog-info.yaml";

  test.describe.configure({ mode: "serial" });

  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
  });

  test.beforeEach(async ({ guestPage }) => {
    uiHelper = new UIhelper(guestPage);
    catalogImport = new CatalogImportPage(guestPage);
    await uiHelper.openSidebar("Catalog");
    await uiHelper.verifyHeading("My Org Catalog");
  });

  test("Import an existing Git repository and verify `Created At` column and value in the Catalog Page", async () => {
    await uiHelper.openSidebar("Self-service");
    await uiHelper.clickButton("Import an existing Git repository");
    await catalogImport.registerExistingComponent(component);
    await uiHelper.openSidebar("Catalog");
    await uiHelper.searchInputPlaceholder("timestamp-test-created");
    await uiHelper.verifyText("timestamp-test-created");
    await uiHelper.verifyColumnHeading(["Created At"], true);
    await uiHelper.verifyRowInTableByUniqueText("timestamp-test-created", [
      /^\d{1,2}\/\d{1,2}\/\d{1,4}, \d:\d{1,2}:\d{1,2} (AM|PM)$/u,
    ]);
  });

  test("Toggle 'CREATED AT' to see if the component list can be sorted in ascending/decending order", async ({
    guestPage,
  }) => {
    const rows = guestPage.getByRole("row").filter({ has: guestPage.getByRole("cell") });
    await expect(rows).not.toHaveCount(0);
    const column = guestPage.getByRole("columnheader", { name: "Created At", exact: true });
    await column.click();
    await column.click();
    await expect(await firstRowCreatedAt(guestPage)).not.toBeEmpty();
  });
});
