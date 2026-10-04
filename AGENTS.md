# iMCP-HTTP agent guide

Build a small native Mac app one owner can understand and maintain. Read `docs/PLAN.md`, `docs/ARCHITECTURE.md`, and the relevant section of `docs/REQUIREMENTS.md` before changing behavior.

## Boundaries

- Use one normal Mac window with a Dock icon and a persistent compact menu-bar panel. Closing the window keeps the server running; Quit stops it. Keep the HTTP core independent.
- Services contain global individual-tool switches. All approved clients share those choices; account-wide access does not mean omitting tool controls.

- SwiftUI displays runtime state and submits owner decisions. Core code must not depend on SwiftUI bindings.
- One app process owns the eventual listener and Apple permissions. Do not introduce a daemon, CLI proxy, hosted service, or remote exposure without a concrete requirement.
- OAuth is the chosen authentication path. Never replace it with trust by client name, an unauthenticated fallback, or a proprietary pairing exchange.
- Client approval is account-wide for globally enabled capabilities. Do not add per-list permission editors or multi-user roles.
- Apple frameworks own Apple data. Do not create a second reminders database.
- Keep transport, authorization, dispatch, and service access separable, but extract interfaces only when needed by a real implementation or test.
- Do not copy SimpleBot/T3 source merely to imitate their UX. Check licenses before any third-party code reuse and preserve attribution.

## Work in complete slices

1. Identify the owning contract and current implementation.
2. Read only the relevant prior-art route in `docs/INSPIRATION.md`.
3. Implement the smallest useful path and its failure behavior.
4. Add meaningful tests at new behavioral boundaries; do not add tests that merely duplicate constants or placeholders.
5. Run `./scripts/check.sh`, review the diff, and state which runtime acceptance remains unverified.

Do not install or reconfigure production integrations during development. Use disposable fixtures and temporary credentials. Never read or mutate real reminders for an automated test. Manual Apple-service acceptance must use identifiable disposable items and confirm cleanup.

Never commit credentials, authorization codes, tokens, signing keys, account data, runtime databases, or logs. Log operation metadata rather than Apple content. Keep generated bundles outside the Vault and out of Git.

## Documentation

`docs/PLAN.md` is the initial implementation plan requested by the owner. Requirements describe intended behavior; architecture and README must distinguish it from implemented behavior. Update the plan as milestones land rather than creating parallel roadmaps.

Operational status and dated next actions belong in the Vault: `Projects/iMCP-HTTP/iMCP-HTTP Status.md`. Keep machine-specific details there; use relative paths and portable instructions in this repository. Consult the Vault's own instructions before editing it.

The repository is private until the owner explicitly authorizes publication. A permissive license does not change repository visibility.
