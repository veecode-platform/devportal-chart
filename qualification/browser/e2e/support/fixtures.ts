import { test as base, type Page } from "@playwright/test";
import { LoginHelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

// The guestPage fixture of upstream's e2e-tests/playwright/support/coverage/test.ts,
// signed in through the library's LoginHelper.
export const test = base.extend<{ guestPage: Page }>({
  guestPage: async ({ page }, use) => {
    await new LoginHelper(page).loginAsGuest();
    await use(page);
  },
});

export { expect } from "@playwright/test";
