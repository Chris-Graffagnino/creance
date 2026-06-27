# Contract — <CapabilityName>Provider

> Skeleton provider contract. One file per swappable seam, listed in
> `.claude/PROJECT.md` → "Architecture boundaries". The contract auditor
> (`.claude/workflow/reviewers/contract-auditor.md`) enforces it: a vendor SDK/API
> called outside this interface, or a vendor-specific type/error/option leaking through
> a public surface, is a **FAIL** (it breaks provider-swappability).
>
> **Worked example:** [`docs/examples/lantern/specs/001-guided-sessions/contracts/audio-synthesis-provider.md`](../../../docs/examples/lantern/specs/001-guided-sessions/contracts/audio-synthesis-provider.md)
> is a fully filled version of this file (the fictional "Lantern" project).

## Purpose

<What capability this seam provides and why it is behind an interface — e.g. the vendor
may change, the license has constraints, or cost must be controlled at one choke point.>

## Interface

```ts
export interface <CapabilityName>Provider {
  /** <method contract — inputs, outputs, error semantics> */
  <method>(input: <InputType>): Promise<<OutputType>>;
}
```

## Semantics & constraints

- **Swappability:** no vendor names, vendor error types, or vendor-specific options in
  this file's types. Concrete implementations adapt vendor responses to these shapes.
- **Error contract:** <how failures surface — typed errors, result unions, retries>.
- **Cost/quota invariants:** <e.g. cache-by-hash never re-bills; calls only on explicit
  user action; the kill-switch is honored> — or "none".
- **Banned vendors/sources:** <name + reason (license, privacy)> — or "none".

## Conformance

<How an implementation proves it satisfies this contract: the shared test suite to pass,
fixtures to run against, or the acceptance gate (e.g. an accuracy threshold) to clear
before the app may build on it.>
