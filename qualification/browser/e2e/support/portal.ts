import { expect, type APIRequestContext } from "@playwright/test";
import { $, requireEnv } from "@red-hat-developer-hub/e2e-test-utils/utils";

// The library sets zx's stdio to inherit, which leaves stdout empty.
const sh = $({ stdio: "pipe" });

export function portalDeployment(): { namespace: string; deployment: string } {
  requireEnv("NAMESPACE", "RELEASE");
  return {
    namespace: process.env.NAMESPACE!,
    deployment: `${process.env.RELEASE!}-developer-hub`,
  };
}

export async function kubectl(...args: string[]): Promise<string> {
  const { namespace } = portalDeployment();
  return (await sh`kubectl -n ${namespace} ${args}`).stdout;
}

// run.sh restarts its port-forward when the old pod goes away, so the portal is
// back once readiness answers through it.
export async function restartPortal(request: APIRequestContext): Promise<void> {
  const { deployment } = portalDeployment();
  await kubectl("rollout", "restart", `deployment/${deployment}`);
  await kubectl("rollout", "status", `deployment/${deployment}`, "--timeout=15m");
  await expect
    .poll(
      async () =>
        (await request.get("/.backstage/health/v1/readiness").catch(() => undefined))?.status(),
      { timeout: 180_000, intervals: [5_000] },
    )
    .toBe(200);
}
