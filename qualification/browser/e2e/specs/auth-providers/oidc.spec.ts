// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/auth-providers/oidc.spec.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b. The cases that reconfigure the deployment
// between logins, the GitHub one and the production-only guest check are left out: they
// need the library's deployment helpers, GitHub credentials or auth.environment
// production. values-oidc.yaml sets the emailLocalPartMatchingUserEntityName resolver
// and a 3-day session upfront. In realm.json, test1's email matches its user entity and
// test2's does not.
import { expect, type APIRequestContext } from "@playwright/test";
import {
  CatalogApiHelper,
  LoginHelper,
  UIhelper,
  getSessionAuthToken,
} from "@red-hat-developer-hub/e2e-test-utils/helpers";
import { requireEnv } from "@red-hat-developer-hub/e2e-test-utils/utils";

import { test } from "../../support/fixtures";

const NO_USER_FOUND_IN_CATALOG_ERROR_MESSAGE =
  /Login failed; caused by Error: Failed to sign-in, unable to resolve user identity. Please verify that your catalog contains the expected User entities that would match your configured sign-in resolver./u;

function password(): string {
  requireEnv("KEYCLOAK_USER_PASSWORD");
  return process.env.KEYCLOAK_USER_PASSWORD!;
}

async function guestToken(request: APIRequestContext): Promise<string> {
  const response = await request.get("/api/auth/guest/refresh", {
    headers: { "X-Requested-With": "XMLHttpRequest" },
  });
  expect(response.status()).toBe(200);
  const body: { backstageIdentity: { token: string } } = await response.json();
  return body.backstageIdentity.token;
}

test.describe("Configure OIDC provider (using RHBK)", () => {
  test.beforeAll(async ({ request }, testInfo) => {
    test.info().annotations.push({
      type: "component",
      description: "authentication",
    });

    // The Keycloak catalog module syncs the realm 15 seconds after the portal starts.
    const token = await guestToken(request);
    await expect
      .poll(() => CatalogApiHelper.entityExists(testInfo.project.use.baseURL!, token, "user", "test1"), {
        timeout: 180_000,
        intervals: [10_000],
      })
      .toBe(true);
  });

  test("Login with OIDC emailLocalPartMatchingUserEntityName resolver", async ({ page }) => {
    const loginHelper = new LoginHelper(page);
    const uiHelper = new UIhelper(page);
    await loginHelper.loginAsKeycloakUser("test1", password());
    await uiHelper.openSidebar("Settings");
    await uiHelper.verifyHeading("Test User1");
    await uiHelper.dismissQuickstartIfVisible();
    await uiHelper.clickButton("Show more");
    await uiHelper.verifyText("RHDH Metadata");
    await loginHelper.signOut();
  });

  test("Login with OIDC emailLocalPartMatchingUserEntityName resolver fails for a user outside the catalog", async ({
    page,
  }) => {
    expect(await new LoginHelper(page).keycloakLogin("test2", password())).toBe("Login successful");
    await new UIhelper(page).verifyAlertErrorMessage(NO_USER_FOUND_IN_CATALOG_ERROR_MESSAGE);
  });

  test(`Confirm the auth cookie lasts the configured sessionDuration`, async ({
    page,
    context,
  }) => {
    await new LoginHelper(page).loginAsKeycloakUser("test1", password());
    await page.reload();

    const cookies = await context.cookies();
    const authCookie = cookies.find((cookie) => cookie.name === "oidc-refresh-token");
    expect(authCookie).toBeDefined();

    const threeDays = 3 * 24 * 60 * 60 * 1000;
    const tolerance = 3 * 60 * 1000;
    const actualDuration = authCookie!.expires * 1000 - Date.now();

    expect(actualDuration).toBeGreaterThan(threeDays - tolerance);
    expect(actualDuration).toBeLessThan(threeDays + tolerance);
  });

  test(`Ingestion of users and groups: verify the user entities and groups are created with the correct relationships`, async ({
    guestPage,
  }, testInfo) => {
    const baseUrl = testInfo.project.use.baseURL!;
    const token = await getSessionAuthToken(guestPage, new UIhelper(guestPage), baseUrl);
    for (const user of ["test1", "test2"]) {
      expect(await CatalogApiHelper.entityExists(baseUrl, token, "user", user)).toBe(true);
    }
    for (const group of ["developers", "admins", "viewers"]) {
      expect(await CatalogApiHelper.entityExists(baseUrl, token, "group", group)).toBe(true);
    }
    expect((await CatalogApiHelper.getGroupMembers(baseUrl, token, "developers")).sort()).toEqual([
      "test1",
      "test2",
    ]);
  });
});
