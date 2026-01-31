# LennyWisdomDB

A SQL Server 2025 vector search sample database built from [Lenny's Podcast](https://www.lennysnewsletter.com/podcast) transcripts. Contains 21K+ semantically chunked Q&A pairs from 270 episodes with product leaders like Brian Chesky, Shreyas Doshi, and Marty Cagan.

## SQL Server 2025 Features Used

Uses **RTM (non-preview) features only**:

- `VECTOR(1024)` - Native vector data type for storing embeddings
- `VECTOR_DISTANCE('cosine', ...)` - Similarity search function

At 21K chunks, brute-force vector search completes in ~75ms. No vector index required at this scale.

## Database Stats

| Metric | Count |
|--------|-------|
| Episodes | 270 |
| Q&A Chunks | 21,571 |
| Chunk Embeddings | 21,571 |
| Search Phrases | 73 |
| Topics | 87 |
| Embedding Model | snowflake-arctic-embed2 (1024 dim) |

## Schema Design

Follows normalized embedding patterns from the [Vector Search in Practice](https://www.sqlskills.com) course:

- **Episodes** - Podcast metadata (guest, title, YouTube URL, publish date)
- **EpisodeChunks** - Q&A pairs with timestamps for YouTube deep-linking
- **ChunkEmbeddings** - 1024-dimension vectors with model versioning
- **search_phrases** - 73 pre-embedded PM questions for instant search
- **Topics** - 87 topic categories mapped from Lenny's index
- **EpisodeTopics** - Many-to-many episode-topic mappings

## Chunking Strategy

**Semantic chunking by Q&A pair** - Each chunk contains Lenny's question plus the guest's complete answer. This preserves context naturally for podcast conversations.

- Max chunk size: 2,500 characters (~625 tokens)
- Long answers split with 15% overlap, question prepended as context
- Sponsor segments stripped automatically
- Timestamps preserved for YouTube linking

## Sample Query

Uses pre-embedded search phrases - no LIKE wildcards needed:

```sql
-- Get pre-computed embedding for "product market fit"
DECLARE @query_embedding VECTOR(1024);
SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'signs you have product market fit and how to find it';

-- Semantic search across all episodes
SELECT TOP 10
    e.guest_name,
    e.episode_title,
    LEFT(ec.chunk_text, 300) AS chunk_preview,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,3)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
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
| [`LennyWisdomDB.bak`](https://github.com/MrJoeSack/LennyWisdomDB/releases/tag/v1.0) | Database backup (~128MB, download from Releases) |
| `scripts/LennyWisdomDB_Schema.sql` | Database and table creation script |
| `scripts/LennyWisdomDB_SampleQueries.sql` | Semantic search queries using search_phrases |
| `scripts/LennyWisdomDB_SearchPhrases_Schema.sql` | Search phrases table schema |
| `scripts/LennyWisdomDB_FavoriteEpisodes_Demo.sql` | Focused demos on select episodes |
| `scripts/lenny_load_episodes.py` | Parse transcripts and load episode metadata |
| `scripts/lenny_load_topics.py` | Load topics from index and map to episodes |
| `scripts/lenny_chunk_qa.py` | Parse Q&A pairs, strip sponsors, apply chunking |
| `scripts/lenny_generate_embeddings.py` | Generate chunk embeddings via Ollama |
| `scripts/lenny_embed_search_phrases.py` | Generate search phrase embeddings |
| `scripts/lenny_fix_data_quality.py` | Data cleanup (duplicates, sponsors, etc.) |

## Requirements

- SQL Server 2025 with VECTOR data type support
- ~2GB disk space for database
- Optional: Ollama with snowflake-arctic-embed2 for query embedding

## Credits

- **Transcript source**: [Lenny Rachitsky](https://twitter.com/lennysan) - "My only ask is that if you do something cool with it, just let me know."
- **Original repo**: [ChatPRD/lennys-podcast-transcripts](https://github.com/ChatPRD/lennys-podcast-transcripts)

## License

Database schema and scripts: MIT License
Transcript content: Subject to Lenny's original terms
