// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/smoke-test.spec.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b. The VeeCode home greets with
// "Welcome back, <name>" where RHDH's says "Welcome back!".
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

import { test } from "../support/fixtures";

test.describe("Smoke test", { tag: "@smoke" }, () => {
  let uiHelper: UIhelper;

  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
  });

  test.beforeEach(({ guestPage }) => {
    uiHelper = new UIhelper(guestPage);
  });

  test("Verify the RHDH instance homepage renders", async () => {
    await uiHelper.verifyHeading(/^Welcome back/);
  });
});
