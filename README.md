# LennyWisdomDB

A SQL Server 2025 vector search sample database built from [Lenny's Podcast](https://www.lennysnewsletter.com/podcast) transcripts. Contains 24,000+ semantically chunked Q&A pairs from 300+ episodes with product leaders like Brian Chesky, Shreyas Doshi, and Marty Cagan.

## SQL Server 2025 Features Used

Uses **RTM (non-preview) features only**:

- `VECTOR(1024)` - Native vector data type for storing embeddings
- `VECTOR_DISTANCE('cosine', ...)` - Similarity search function

At 24K chunks, brute-force vector search completes in ~75ms. No vector index required at this scale.

## Database Stats

| Metric | Count |
|--------|-------|
| Episodes | 270 |
| Q&A Chunks | 21,571 |
| Embeddings | 21,571 |
| Topics | 87 |
| Embedding Model | snowflake-arctic-embed2 (1024 dim) |

## Schema Design

Follows normalized embedding patterns from the [Vector Search in Practice](https://www.sqlskills.com) course:

- **Episodes** - Podcast metadata (guest, title, YouTube URL, publish date)
- **EpisodeChunks** - Q&A pairs with timestamps for YouTube deep-linking
- **ChunkEmbeddings** - 1024-dimension vectors with model versioning
- **Topics** - 87 topic categories mapped from Lenny's index
- **EpisodeTopics** - Many-to-many episode-topic mappings

## Chunking Strategy

**Semantic chunking by Q&A pair** - Each chunk contains Lenny's question plus the guest's complete answer. This preserves context naturally for podcast conversations.

- Max chunk size: 2,500 characters (~625 tokens)
- Long answers split with 15% overlap, question prepended as context
- Sponsor segments stripped automatically
- Timestamps preserved for YouTube linking

## Sample Queries

```sql
-- Semantic search: find chunks about roadmaps
DECLARE @query_embedding VECTOR(1024);
SELECT TOP 1 @query_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%roadmap%';

SELECT TOP 10
    e.guest_name,
    LEFT(ec.chunk_text, 300) AS preview,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
```

## Files

| File | Description |
|------|-------------|
| [`LennyWisdomDB.bak`](https://github.com/MrJoeSack/LennyWisdomDB/releases/download/v1.0/LennyWisdomDB.bak) | Full database backup (~128MB, download from Releases) |
| `scripts/LennyWisdomDB_Schema.sql` | Database and table creation script |
| `scripts/LennyWisdomDB_SampleQueries.sql` | Example semantic search queries |
| `scripts/LennyWisdomDB_FavoriteEpisodes_Demo.sql` | Focused demos on select episodes |
| `scripts/lenny_load_episodes.py` | Parse transcripts and load episode metadata |
| `scripts/lenny_load_topics.py` | Load topics from index and map to episodes |
| `scripts/lenny_chunk_qa.py` | Parse Q&A pairs, strip sponsors, apply chunking |
| `scripts/lenny_generate_embeddings.py` | Generate embeddings via Ollama batch API |
| `scripts/lenny_fix_data_quality.py` | Data cleanup script (duplicates, sponsors, etc.) |

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
