# Federal Case Law & Live Lookup — Project Scope

**Status:** Stub — not scoped yet
**Owner:** Jeremy Berger
**Relationship to `federal-statutes-regs-rag`:** sibling project, explicitly
out of that project's scope per its own `SCOPE.md` §"Explicitly out of
scope, tracked elsewhere." This file exists so the boundary has somewhere
real to point to; it is not yet a worked plan.

## Why this is a separate system, not a mode of the statutes/regs RAG

Federal case law lacks the three properties that make statutes/regs
tractable to pre-index (see `federal-statutes-regs-rag/SCOPE.md` §2):

- No single "current" text per legal issue — multiple opinions can bear on
  the same question, and which one controls depends on jurisdiction,
  procedural posture, and time.
- Validity is not just about document freshness — a case can be
  overruled, distinguished, or superseded without the opinion's own text
  changing, so a citation/precedent validity graph is load-bearing in a way
  it isn't for statute/reg text.
- Change detection and re-indexing bounds are not well-defined the way a
  new Federal Register entry or Congress session's bounded impact is.

This likely points toward a live-query architecture (fetch + validate at
query time) rather than a pre-built index that assumes staleness is
boundable — the opposite tradeoff from the statutes/regs project. That
architectural difference is why the two are separate systems with separate
failure modes and separate maintenance burdens, not two modes of one
pipeline.

## Not yet done

- Data source survey (equivalent of the statutes/regs project's §3 table —
  e.g. CourtListener/RECAP, Caselaw Access Project, PACER, commercial
  citators)
- Citation/precedent validity graph design
- Live-fetch-and-inherit architecture (the "live worker template" pattern
  referenced as out-of-scope elsewhere)
- Effort estimate

## Non-goals (inherited from the sibling project's framing)

- Legal advice generation — any future output here is a research aid with
  citations and validity flags, not a legal conclusion
- State or municipal case law
