# Behavior requirements

All server requirements below are planned. Current behavior is described in `ARCHITECTURE.md`.

## OAuth and owner approval

- Standard MCP-compatible OAuth authorization code + PKCE S256. No custom client software or repeated manual token pasting in the intended experience.
- Authenticate the owner's decision through the native app, bound to one pending authorization request. A browser page or client-supplied name alone cannot approve itself.
- Keep the first UI minimal: client label, explanation of account-wide enabled access, Approve, Deny. Show the client identifier/details when needed to distinguish requests.
- The grant persists until explicitly revoked. Store a distinct grant per authorized connection; do not use one shared owner API key.
- Pending requests and codes expire; codes are single-use, bound to client, callback, resource, and PKCE challenge. Bound pending requests and attempts to prevent unbounded approval prompts.
- Serve protected-resource and authorization-server metadata appropriate to the negotiated MCP/OAuth profile. Use a stable issuer/resource and strict registered callback validation, including standard loopback-port rules.
- Validate issuer, resource/audience, credential expiry, grant revocation, and scope on every applicable exchange/request. Use one account-access scope initially if needed by the protocol; no granular permission editor.
- Access/refresh credentials remain out of URLs, tool results, logs, repository config, screenshots, and support dumps. Authorization-code callbacks follow the standard flow and must not be logged.
- Rotate refresh credentials atomically and define replay handling; revoked grants cannot refresh. A credential refresh is not a new owner approval.
- Client labels are untrusted display data. They do not establish application identity or ownership.
- The app's local controls own authorization management; MCP tools do not issue grants or approve new clients.

## HTTP and lifecycle

- Loopback binding only; reject unexpected Host and Origin values to prevent browser-origin abuse. Implement standard MCP Origin behavior, including rejection of an invalid supplied Origin and support for legitimate native clients without one.
- No unauthenticated tool calls, including on loopback. Protocol discovery may remain public where required.
- No wildcard CORS or implicit authentication fallback. Bound request sizes, connection count, and pending work.
- Bind failures are visible as failures, never a green Running state. Stop/Quit closes listeners and live sessions.
- Restart recovers durable grants and revocations, not pending approvals or in-progress tool calls.
- No automatic retry of Apple mutations after an unknown outcome.

## Tools and Apple access

- All approved clients share globally enabled services across the current macOS user's available accounts. No per-list restrictions in the first release.
- Global enablement and current OS permissions are enforced on calls, not only when listing tools.
- The tool list contains implemented, available, enabled tools; planned service names are never advertised as working tools.
- Preserve the iMCP suite as the initial inventory, subject to adapter acceptance and OS/developer capability constraints.
- Use explicit read-only/destructive annotations and machine-readable errors/results. An annotation is not access control.
- The app does not promise tool-call approval dialogs inside Codex; client-side approval policy remains the client's responsibility.

## Reminders: first useful slice

- List and fetch return opaque list/item identifiers and account/source context so duplicate names are distinguishable.
- Editing and deletion require a specific identifier. Stale, missing, inaccessible, and read-only targets fail clearly.
- Editing supports title, notes, priority, and due date first; distinguish omission from explicit clearing. List moves follow once verified.
- Reject invalid dates and unknown targets; do not silently discard invalid input or change a different list.
- Date-only deadlines remain date-only. Timed deadlines preserve the documented timezone behavior.
- Delete operates on the exact identified item, including completed reminders. Return success only after framework confirmation; subsequent read verifies absence during acceptance.
- Re-fetch before mutation where needed to avoid overwriting unrelated native fields; document any unavoidable concurrency limitations.
- Native subtasks, tags, sections, recurrence editing, and bulk operations are later feasibility/implementation slices. Never emulate native features in notes without explicit product agreement.

## Verification

When implementation starts, add Swift tests for validation, authorization transitions, dispatch enforcement, and adapter behavior using fakes/disposable storage. Add real listener tests for protocol boundaries. CI must run actual tests once present.

Manual acceptance uses Codex and disposable Apple data: prove successful behavior, rejection, revocation, restart, and cleanup. Neither source inspection, open TCP ports, a successful build, nor permission settings alone establish acceptance.

## References

- [MCP authorization](https://modelcontextprotocol.io/specification/latest/basic/authorization)
- [MCP transports](https://modelcontextprotocol.io/specification/latest/basic/transports)
- [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)

Consult current specifications during implementation; record the tested protocol and client versions with acceptance evidence.
