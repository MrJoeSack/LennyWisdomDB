# LennyWisdomDB

A SQL Server 2025 vector search sample database built from [Lenny's Podcast](https://www.lennysnewsletter.com/podcast) transcripts. Contains 21K+ semantically chunked Q&A pairs from 270 episodes with product leaders like Brian Chesky, Shreyas Doshi, and Marty Cagan.

Implements **production-grade RAG patterns** including parent-child chunk architecture, hybrid search, contextualized embeddings, and search audit logging.

## SQL Server 2025 Features Used

Uses **RTM (non-preview) features only**:

- `VECTOR(1024)` - Native vector data type for storing embeddings
- `VECTOR_DISTANCE('cosine', ...)` - Similarity search function
- Full-text search for hybrid BM25 + vector queries

At 21K chunks, brute-force vector search completes in ~75ms. No vector index required at this scale.

## Database Stats

| Metric | Count |
|--------|-------|
| Episodes | 270 |
| Q&A Chunks | 21,571 |
| Unique Q&A Groups | 18,287 |
| Chunk Embeddings | 21,571 |
| Search Phrases | 73 |
| Topics | 87 |
| Embedding Model | snowflake-arctic-embed2 (1024 dim) |

## Production RAG Patterns

This database demonstrates state-of-the-art patterns for production RAG systems:

| Pattern | Implementation | Purpose |
|---------|----------------|---------|
| **Parent-Child Chunks** | `qa_group_id` column | Links split chunks to parent Q&A for deduplication |
| **Hybrid Search** | Full-text + vector with RRF | Combines keyword (BM25) and semantic search |
| **Contextualized Embeddings** | `contextualized_text` column | Prepends episode/guest context per Anthropic research |
| **Pre-filtering** | `content_type`, topic joins | Filter before vector search for efficiency |
| **Search Audit** | `SearchLog`, `SearchResults` tables | Query logging for debugging and analytics |
| **Embedding Versioning** | `EmbeddingModels` table with version | Track model provenance for reproducibility |
| **Token Tracking** | `token_count` column | LLM context management (not just char_count) |

## Schema Design

Follows normalized embedding patterns with SOTA enhancements:

- **Episodes** - Podcast metadata with data lineage tracking
- **EpisodeChunks** - Q&A pairs with contextualized text, token counts, content types
- **ChunkEmbeddings** - 1024-dimension vectors with generation timestamps
- **search_phrases** - 73 pre-embedded PM questions for instant search
- **SearchLog / SearchResults** - Audit trail for search analytics
- **Topics** - 87 topic categories for pre-filtering

## Chunking Strategy

**Semantic chunking by Q&A pair** - Each chunk contains Lenny's question plus the guest's complete answer. This preserves context naturally for podcast conversations.

- Max chunk size: 2,500 characters (~625 tokens)
- Long answers split with 15% overlap, question prepended as context
- Split chunks linked via `qa_group_id` for parent document retrieval
- Sponsor segments stripped automatically
- Timestamps preserved for YouTube linking
- Intro content tagged for optional filtering

## Sample Query: Parent Document Retrieval

Best practice pattern - retrieve by chunk, dedupe by Q&A group:

```sql
DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'signs you have product market fit and how to find it';

-- Retrieve best chunk per Q&A group (eliminates duplicates)
SELECT qa_group_id, guest_name, question, answer, youtube_link, best_distance
FROM (
    SELECT
        ec.qa_group_id,
        e.guest_name,
        LEFT(ec.speaker_question, 150) AS question,
        LEFT(ec.speaker_answer, 300) AS answer,
        CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS distance,
        MIN(CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)))
            OVER (PARTITION BY ec.qa_group_id) AS best_distance,
        ROW_NUMBER() OVER (PARTITION BY ec.qa_group_id
            ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding)) AS rn
    FROM ChunkEmbeddings ce
    JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN Episodes e ON ec.episode_id = e.episode_id
) ranked
WHERE rn = 1
ORDER BY best_distance
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

## Search Phrase Categories

| Category | Phrases | Examples |
|----------|---------|----------|
| strategy | 10 | product vision, roadmaps, prioritization |
| leadership | 10 | managing up, feedback, influence |
| career | 10 | promotions, IC vs manager, interviews |
| growth | 10 | metrics, PLG, retention, churn |
| ai | 8 | AI products, AI tools for PMs |
| execution | 8 | meetings, PRDs, shipping faster |
| discovery | 7 | user research, validation |
| culture | 5 | hiring PMs, onboarding |
| startup | 5 | founder advice, fundraising |

## Files

| File | Description |
|------|-------------|
| [`LennyWisdomDB.bak`](https://github.com/MrJoeSack/LennyWisdomDB/releases) | Database backup (~150MB, download from Releases) |
| `scripts/LennyWisdomDB_Schema.sql` | Full schema with SOTA columns and tables |
| `scripts/LennyWisdomDB_SOTA_Migration.sql` | Migration script to add SOTA features |
| `scripts/LennyWisdomDB_SOTA_Queries.sql` | Demo queries for all RAG patterns |
| `scripts/LennyWisdomDB_SampleQueries.sql` | Basic semantic search using search_phrases |
| `scripts/LennyWisdomDB_FavoriteEpisodes_Demo.sql` | Focused demos on select episodes |
| `scripts/LennyWisdomDB_SearchPhrases_Schema.sql` | Search phrases table and data |
| `scripts/lenny_load_episodes.py` | Parse transcripts and load episode metadata |
| `scripts/lenny_load_topics.py` | Load topics from index and map to episodes |
| `scripts/lenny_chunk_qa.py` | Parse Q&A pairs, strip sponsors, apply chunking |
| `scripts/lenny_generate_embeddings.py` | Generate chunk embeddings via Ollama |
| `scripts/lenny_embed_search_phrases.py` | Generate search phrase embeddings |
| `scripts/lenny_fix_data_quality.py` | Data cleanup (duplicates, sponsors, etc.) |

## Requirements

- SQL Server 2025 with VECTOR data type support
- ~2GB disk space for database
- Optional: Ollama with snowflake-arctic-embed2 for custom query embedding

## Credits

- **Transcript source**: [Lenny Rachitsky](https://twitter.com/lennysan) - "My only ask is that if you do something cool with it, just let me know."
- **Original repo**: [ChatPRD/lennys-podcast-transcripts](https://github.com/ChatPRD/lennys-podcast-transcripts)

## License

Database schema and scripts: MIT License
Transcript content: Subject to Lenny's original terms
