# LennyWisdomDB

A SQL Server 2025 vector search sample database. 21K chunks from 270 Lenny's Podcast episodes, pre-embedded and ready to query.

**For:** SQL Server developers exploring vector search, embeddings, or RAG with real data instead of toy examples.

## Quickstart

1. **Download** [`LennyWisdomDB.bak`](https://github.com/MrJoeSack/LennyWisdomDB/releases/tag/v1.1) (166MB)
2. **Restore** in SQL Server 2025 (RTM, not preview)
3. **Run a semantic search:**

```sql
DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'what bad strategy looks like and how to avoid it';

SELECT TOP 5
    e.guest_name,
    ec.speaker_question,
    ec.speaker_answer,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)) AS distance
FROM dbo.ChunkEmbeddings ce
JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
WHERE ec.split_part = 1
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query);
```

## What's Inside

| Metric | Value |
|--------|-------|
| Episodes | 270 |
| Q&A Chunks | 21,571 |
| Embedding Model | snowflake-arctic-embed2 (1024 dim) |
| Pre-embedded Search Phrases | 1,076 |
| Topics | 87 |

## Features

| Feature | How It Works |
|---------|--------------|
| **Vector Search** | `VECTOR(1024)` type + `VECTOR_DISTANCE('cosine', ...)` |
| **Hybrid Search** | Full-text (BM25) + vector with Reciprocal Rank Fusion |
| **Chunk Deduplication** | `qa_group_id` links split chunks to parent Q&A |
| **Contextualized Embeddings** | Episode/guest context prepended before embedding |

## Schema

**Content**
| Table | Purpose |
|-------|---------|
| `Episodes` | Podcast metadata (guest, title, video_id, publish_date) |
| `EpisodeChunks` | Q&A segments with timestamps for YouTube deep-linking |
| `Topics` / `EpisodeTopics` | 87 topic categories for filtering |

**Vectors**
| Table | Purpose |
|-------|---------|
| `ChunkEmbeddings` | 1024-dim vector per chunk |
| `EmbeddingModels` | Model versioning (name, dimensions, provider) |
| `search_phrases` | 1,076 pre-embedded queries by category |

**Deduplication columns** in `EpisodeChunks`:
- `qa_group_id` - links split chunks to same Q&A
- `split_part` - 1, 2, 3... for multi-part answers
- `content_type` - 'intro' or 'main' for pre-filtering
- `contextualized_text` - enriched text used for embedding

## Chunking Strategy

Each chunk = one complete Q&A exchange (Lenny's question + guest's answer). This preserves conversational context naturally.

- Target size: 2,500 chars (~625 tokens)
- Long answers split with 15% overlap, linked via `qa_group_id`
- Sponsor segments stripped
- Timestamps preserved for YouTube linking

## Files

| File | Description |
|------|-------------|
| [`LennyWisdomDB.bak`](https://github.com/MrJoeSack/LennyWisdomDB/releases/tag/v1.1) | Database backup (166MB) |
| [`LennyWisdomDB_Queries.sql`](scripts/LennyWisdomDB_Queries.sql) | Sample queries (semantic, hybrid, filtered, parent retrieval) |

## Requirements

- SQL Server 2025 RTM with VECTOR support

## Credits

- **Transcripts**: [Lenny Rachitsky](https://x.com/lennysan) via [ChatPRD/lennys-podcast-transcripts](https://github.com/ChatPRD/lennys-podcast-transcripts)
- **Embeddings**: Generated via Ollama (snowflake-arctic-embed2)

## License

Schema and scripts: MIT. Transcript content subject to Lenny's original terms.
