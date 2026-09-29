// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/configuration-test/config-map.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b. Upstream edits app-config-rhdh through its
// RuntimeHarness; this edits the chart's <release>-developer-hub-app-config ConfigMap,
// the last --config file of the portal, so its app.title wins over the product's.
import { LoginHelper, UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";
import { parse, stringify } from "yaml";
import { test, expect } from "@playwright/test";

import { kubectl, portalDeployment, restartPortal } from "../../support/portal";

test.describe("Change app-config at e2e test runtime", () => {
  test.beforeAll(() => {
    test.info().annotations.push(
      {
        type: "component",
        description: "configuration",
      },
      {
        type: "namespace",
        description: portalDeployment().namespace,
      },
    );
  });

  test("Verify title change after ConfigMap modification", async ({ page, request }) => {
    test.setTimeout(20 * 60 * 1000);
    const configMapName = `${portalDeployment().deployment}-app-config`;
    const dynamicTitle = generateDynamicTitle();

    const configMap: { data: Record<string, string> } = JSON.parse(
      await kubectl("get", "configmap", configMapName, "-o", "json"),
    );
    const appConfig = parse(configMap.data["app-config.yaml"]);
    appConfig.app.title = dynamicTitle;
    await kubectl(
      "patch",
      "configmap",
      configMapName,
      "--type=merge",
      "-p",
      JSON.stringify({ data: { "app-config.yaml": stringify(appConfig) } }),
    );
    await restartPortal(request);

    await new LoginHelper(page).loginAsGuest();
    await new UIhelper(page).openSidebar("Home");
    expect(await page.title()).toContain(dynamicTitle);
  });
});

function generateDynamicTitle() {
  const timestamp = new Date().toISOString().replaceAll(/[-:.]/gu, "");
  return `New Title - ${timestamp}`;
}
