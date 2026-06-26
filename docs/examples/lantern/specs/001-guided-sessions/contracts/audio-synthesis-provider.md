# Contract — AudioSynthesisProvider

> **Illustrative example — not live config.** Part of the *fictional* Lantern worked-example
> set (a filled counterpart to
> [`specs/000-template/contracts/example-provider.md`](../../../../../../specs/000-template/contracts/example-provider.md)).
> The contract auditor (`.claude/workflow/reviewers/contract-auditor.md`) enforces it: a vendor
> SDK/API called outside this interface, or a vendor-specific type/error/option leaking through
> a public surface, is a **FAIL**. See [`docs/examples/README.md`](../../../../README.md).

## Purpose

Lantern turns a guided-session script into spoken narration through a text-to-speech vendor.
That capability sits behind an interface for three reasons named in the constitution: the
vendor may change (Principle 3 keeps it swappable), cost must be controlled at one choke point
(a content-hash cache so identical text is never re-billed), and the privacy boundary must be
auditable in one place (no behavioral data rides the synthesis call — Principle 2).

## Interface

```ts
export interface AudioSynthesisProvider {
  /**
   * Synthesize narration for one session segment.
   * - Implementations MUST be pure with respect to `text` + `voice`: identical inputs
   *   return byte-identical audio, so the caller can cache by content hash.
   * - MUST NOT attach analytics, device, or user identifiers to the request.
   * Throws `SynthesisError` (a neutral, vendor-agnostic error) on failure.
   */
  synthesize(input: NarrationRequest): Promise<AudioClip>;
}

export interface NarrationRequest {
  text: string;          // the segment script — no PII, no per-user data
  voice: VoiceId;        // a neutral voice identifier, not a vendor SKU
  speedPct: number;      // 50–150; playback pacing
}

export interface AudioClip {
  bytes: Uint8Array;     // encoded audio
  contentHash: string;   // hash of (text, voice, speedPct) — the cache key
}
```

## Semantics & constraints

- **Swappability:** no vendor names, vendor error types, or vendor-specific options in this
  file's types. A concrete implementation adapts the vendor's response to `AudioClip` and maps
  vendor failures to `SynthesisError`.
- **Error contract:** failures surface as a typed `SynthesisError` (e.g. `rate_limited`,
  `unavailable`, `bad_request`); callers retry only `rate_limited`/`unavailable`, with backoff.
- **Cost/quota invariants:** the caller resolves `contentHash` against the cache *before*
  calling `synthesize`; a cache hit never re-bills. Synthesis happens only on an explicit user
  play/preload action — never speculatively.
- **Banned vendors/sources:** **TrackKit Analytics** or any SDK that derives behavioral
  signals from the request — banned (privacy; Principle 2). The request carries no identifiers,
  so a conformant implementation has nothing to leak.

## Conformance

An implementation proves it satisfies this contract by passing the shared provider test suite:
the purity/cache test (identical `NarrationRequest` ⇒ identical `contentHash`, second call
served from cache with no vendor call), the error-mapping test (each vendor failure maps to the
right `SynthesisError`), and the import-scope check (no vendor TTS symbol imported outside the
provider adapter). Lantern's `verify` job runs all three before any screen may build on the seam.
