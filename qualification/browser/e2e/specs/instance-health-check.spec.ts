// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/instance-health-check.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b: plain Playwright test instead of the
// coverage fixture.
import { test, expect } from "@playwright/test";

test.describe("Application health check", () => {
  test.beforeAll(() => {
    test.info().annotations.push({
      type: "component",
      description: "core",
    });
  });

  test("Application health check", async ({ request }) => {
    const healthCheckEndpoint = "/healthcheck";

    const response = await request.get(healthCheckEndpoint);

    const responseBody: unknown = await response.json();

    expect(response.status()).toBe(200);

    expect(responseBody).toHaveProperty("status", "ok");
  });
});
