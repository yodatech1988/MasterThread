# Federal Statutes & Regulations RAG — Project Scope

**Status:** Scoping / not started
**Owner:** Jeremy Berger
**Scope boundary:** Federal statutes (U.S. Code) and regulations (CFR /
Federal Register) only. Full pre-built index, not live lookup.

**Explicitly out of scope, tracked elsewhere:**
- Federal case law and any citation/precedent validity graph
- Any "live worker template" / on-demand-fetch architecture
- These live in a separate project as a distinct system with its own
  scope, since the architecture, failure modes, and maintenance burden are
  fundamentally different (index-and-refresh vs. live-query-and-inherit).
  See `docs/projects/federal-caselaw-live-lookup/SCOPE.md`.

## 1. Problem statement

Build a RAG system that indexes the actual text of federal statutes (U.S.
Code) and federal regulations (CFR, informed by the Federal Register) so
that questions can be answered with retrieval-grounded, citable answers —
without requiring a live API call per query.

This is the "do it properly" track: full ingestion, structure-aware
chunking, embeddings, retrieval, and an update pipeline to keep the index
current as law changes.

## 2. Why statutes/regs (and not case law) are tractable to index

- Single canonical source of truth per document (there is one current text
  of a given USC section or CFR part at any point in time).
- Versioned and machine-readable at the source (USLM XML via GovInfo, eCFR's
  structured API) — no OCR, no scraping ambiguity.
- Change detection is well-defined: a new Federal Register entry or a new
  Congress session triggers a known, bounded re-index of the affected
  section(s), not the whole corpus.

Case law lacks all three properties (no single "current" text per issue,
validity depends on a citation graph, not just document freshness) — which
is exactly why it's scoped as a separate, non-indexed system elsewhere.

## 3. Data sources

| Domain | Source | Access | Notes |
|---|---|---|---|
| U.S. Code | GovInfo Bulk Data (USLM XML) | Free, bulk | Canonical source for initial + full re-index |
| U.S. Code | GovInfo API | Free, REST, API key | Useful for detecting what changed since last index |
| CFR (current) | eCFR API | Free, REST | Primary source for current regulation text |
| Federal Register | FederalRegister.gov API | Free, REST | Drives change-detection / re-index triggers |

## 4. Pipeline phases

1. **Ingestion** — pull USLM XML (USC) and eCFR structured text (CFR) in full
   for initial build.
2. **Structure-aware chunking** — preserve the legal hierarchy (title →
   chapter → section → subsection) as chunk boundaries; attach relevant
   definitions sections rather than splitting them away from the text that
   depends on them. This is the highest-leverage design decision in the
   whole project — generic recursive text splitters will silently degrade
   answer quality.
3. **Embedding + vector store** — standard once chunks are well-formed
   (pgvector / Qdrant / Weaviate all viable at this scale).
4. **Retrieval + reranking** — retrieval plus a reranking pass, with citation
   metadata (title/section number, effective date) carried through to the
   final answer.
5. **Grounding / anti-hallucination pass** — verify the generated answer's
   claims are actually supported by the retrieved chunks before returning it;
   refuse or hedge rather than answer from parametric knowledge when
   retrieval comes up empty or ambiguous.
6. **Update pipeline** — scheduled diffing against GovInfo/eCFR/Federal
   Register to detect changed sections and re-index only what changed,
   rather than a full rebuild each cycle.

## 5. Open questions to resolve before build

1. Query pattern: single-section lookups vs. cross-title research questions?
   Affects chunk size and retrieval-k tuning.
2. Update cadence requirement: daily? weekly? Tied directly to how tight the
   Federal Register diffing needs to be.
3. Consumer: personal research tool vs. anything client-facing for
   HandyMansfield (e.g. building-code/compliance questions)? Affects how
   much disclaimer/liability framing the output needs.
4. Acceptable staleness window between a law changing and the index
   reflecting it.

## 6. Effort estimate

| Phase | Estimate |
|---|---|
| Source integration (GovInfo + eCFR + Federal Register) | 1–3 weeks |
| Structure-aware chunking design + implementation | 1–2 weeks |
| Embedding + vector store setup | few days |
| Retrieval + reranking + citation enforcement | 2–3 weeks |
| Grounding/verification pass | 1–2 weeks |
| Update/diff pipeline | 1–2 weeks |
| **v1 MVP total** | **~6–10 weeks**, one person, federal statutes + regs only |

## 7. Non-goals for this project

- Federal case law (separate project — `federal-caselaw-live-lookup`)
- Any live-fetch / no-index architecture (separate project)
- State or municipal law/regulations
- Legal advice generation — outputs are retrieval-grounded research aids
  with citations, not legal conclusions
