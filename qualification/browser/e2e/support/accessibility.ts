// Adapted from redhat-developer/rhdh e2e-tests/playwright/utils/accessibility.ts at
// 0a2efdf3112b43b331b58df5c0fad7190a28703b: the library's runAccessibilityTests is not
// exported from its helpers and fails on any violation, while upstream fails only on
// critical ones.
import { AxeBuilder } from "@axe-core/playwright";
import { type Page, type TestInfo } from "@playwright/test";
import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";

export async function runAccessibilityTests(
  page: Page,
  testInfo: TestInfo,
  attachName = "accessibility-scan-results.violations.json",
) {
  await new UIhelper(page).waitForLoad(60_000);

  const accessibilityScanResults = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .disableRules([
      "color-contrast",
      // Known global shell violations tracked under RHDHPLAN-954.
      "aria-progressbar-name",
      "list",
      "nested-interactive",
    ])
    .analyze();
  await testInfo.attach(attachName, {
    body: JSON.stringify(accessibilityScanResults.violations, null, 2),
    contentType: "application/json",
  });

  const criticalViolations = accessibilityScanResults.violations.filter(
    (violation) => violation.impact === "critical",
  );

  if (criticalViolations.length > 0) {
    const summary = criticalViolations
      .map((violation) => `${violation.id} (${violation.impact})`)
      .join(", ");
    throw new Error(
      `Accessibility scan found ${criticalViolations.length} critical violation(s): ${summary}`,
    );
  }
}
