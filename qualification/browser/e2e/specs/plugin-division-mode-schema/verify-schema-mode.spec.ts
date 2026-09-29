// Adapted from redhat-developer/rhdh e2e-tests/playwright/e2e/plugin-division-mode-schema/verify-schema-mode.spec.ts
// at 0a2efdf3112b43b331b58df5c0fad7190a28703b. Upstream reaches PostgreSQL with the pg
// client through a port-forward and patches the deployment's env; this runs psql inside
// the run's PostgreSQL pod and moves the portal to a NOCREATEDB user through the chart's
// runtime Secret and app-config ConfigMap.
import { randomBytes } from "node:crypto";

import { UIhelper } from "@red-hat-developer-hub/e2e-test-utils/helpers";
import { expect } from "@playwright/test";
import { parse, stringify } from "yaml";

import { test } from "../../support/fixtures";
import { kubectl, portalDeployment, restartPortal } from "../../support/portal";

const dbName = "devportal_schema";
const dbUser = "devportal_schema";

function psql(sql: string, database = "devportal"): Promise<string> {
  return kubectl(
    "exec",
    "deploy/devportal-db",
    "--",
    "psql",
    "-U",
    "devportal",
    "-d",
    database,
    "-v",
    "ON_ERROR_STOP=1",
    "-tAc",
    sql,
  );
}

// A retried beforeAll runs again in a new worker, so the role and database may exist.
async function tolerateExisting(sql: string, whenExisting?: string): Promise<void> {
  try {
    await psql(sql);
  } catch (error) {
    const stderr = typeof error === "object" && error !== null && "stderr" in error ? String(error.stderr) : "";
    if (!stderr.includes("already exists")) throw error;
    if (whenExisting !== undefined) await psql(whenExisting);
  }
}

test.describe("Verify pluginDivisionMode: schema", () => {
  test.beforeAll(async ({ request }) => {
    test.setTimeout(20 * 60 * 1000);
    test.info().annotations.push(
      { type: "component", description: "data-management" },
      { type: "namespace", description: portalDeployment().namespace },
    );

    const password = randomBytes(16).toString("hex");
    await tolerateExisting(
      `CREATE USER ${dbUser} WITH PASSWORD '${password}' NOSUPERUSER NOCREATEDB`,
      `ALTER USER ${dbUser} WITH PASSWORD '${password}' NOSUPERUSER NOCREATEDB`,
    );
    await tolerateExisting(`CREATE DATABASE ${dbName} OWNER ${dbUser}`);
    await kubectl(
      "patch",
      "secret",
      "veecode-runtime-secrets",
      "--type=merge",
      "-p",
      JSON.stringify({ stringData: { PG_USER: dbUser, PG_PASSWORD: password, PG_DATABASE: dbName } }),
    );

    const configMapName = `${portalDeployment().deployment}-app-config`;
    const configMap: { data: Record<string, string> } = JSON.parse(
      await kubectl("get", "configmap", configMapName, "-o", "json"),
    );
    const appConfig = parse(configMap.data["app-config.yaml"]);
    appConfig.backend.database.pluginDivisionMode = "schema";
    appConfig.backend.database.ensureSchemaExists = true;
    await kubectl(
      "patch",
      "configmap",
      configMapName,
      "--type=merge",
      "-p",
      JSON.stringify({ data: { "app-config.yaml": stringify(appConfig) } }),
    );
    await restartPortal(request);
  });

  test("Verify database user has restricted permissions", async () => {
    expect((await psql(`SELECT rolcreatedb FROM pg_roles WHERE rolname = '${dbUser}'`)).trim()).toBe("f");
  });

  test("Verify RHDH is accessible with schema mode", async ({ guestPage }) => {
    await new UIhelper(guestPage).verifyHeading(/^Welcome back/);
    const schema = await psql(
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'catalog'",
      dbName,
    );
    expect(schema.trim()).toBe("catalog");
  });
});
