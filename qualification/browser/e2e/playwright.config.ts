import { defineConfig, devices } from "@playwright/test";

const out = process.env.OUT ?? ".";
const keycloakForward = new URL(process.env.KEYCLOAK_URL ?? "http://localhost:18080").host;
const restartSpecs = ["**/configuration-test/config-map.spec.ts", "**/plugin-division-mode-schema/*.spec.ts"];

// A plain config: the library's own defineConfig expects one OpenShift deployment
// per project, and run.sh replaces that with the KinD install.
export default defineConfig({
  testDir: "specs",
  outputDir: `${out}/test-results`,
  timeout: 180_000,
  expect: { timeout: 15_000 },
  retries: 1,
  workers: 1,
  forbidOnly: true,
  reporter: [["list"], ["html", { open: "never", outputFolder: `${out}/playwright-report` }]],
  use: {
    ...devices["Desktop Chrome"],
    baseURL: process.env.BASE_URL ?? "http://localhost:17007",
    viewport: { width: 1920, height: 1080 },
    actionTimeout: 15_000,
    navigationTimeout: 60_000,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    launchOptions: { args: [`--host-resolver-rules=MAP keycloak ${keycloakForward}`] },
  },
  projects: [
    // The two specs that restart the portal run after the others, pass or fail.
    { name: "portal", testIgnore: restartSpecs, teardown: "restarts" },
    { name: "restarts", testMatch: restartSpecs },
  ],
});
