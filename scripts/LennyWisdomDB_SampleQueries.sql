/*
    LennyWisdomDB - Sample Semantic Search Queries

    SQL Server 2025 Vector Search - RTM (non-preview) features only:
    - VECTOR(1024) data type for storing embeddings
    - VECTOR_DISTANCE('cosine', ...) for similarity search

    This database contains 24,000+ Q&A chunks from 300+ episodes of Lenny's Podcast,
    embedded with snowflake-arctic-embed2 (1024 dimensions).

    At 24K chunks, brute-force VECTOR_DISTANCE search completes in ~75ms.
    No vector index required at this scale.

    Prerequisites:
    - SQL Server 2025 with VECTOR support
    - Ollama running locally with snowflake-arctic-embed2 model for query embedding
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- QUERY 1: Basic semantic search using VECTOR_DISTANCE
-- Find chunks most similar to a query (requires embedding the query first)
-- ============================================================================

-- This example uses a pre-computed query embedding
-- In production, call Ollama API to embed the query text first

DECLARE @query_embedding VECTOR(1024);

-- Get an example embedding to use as query (borrowing from a roadmap-related chunk)
SELECT TOP 1 @query_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%roadmap%';

-- Semantic search: find similar chunks
SELECT TOP 10
    ec.chunk_id,
    e.guest_name,
    e.episode_title,
    LEFT(ec.chunk_text, 300) AS chunk_preview,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE ce.embedding IS NOT NULL
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 2: Filter by guest + semantic search
-- "What did Brian Chesky say about leadership?"
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

-- Borrow embedding from a leadership-related chunk
SELECT TOP 1 @query_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%leadership%' AND ec.chunk_text LIKE '%detail%';

SELECT TOP 10
    ec.chunk_id,
    e.guest_name,
    LEFT(ec.speaker_question, 200) AS question,
    LEFT(ec.speaker_answer, 300) AS answer_preview,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.guest_name = 'Brian Chesky'
  AND ce.embedding IS NOT NULL
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 3: Filter by topic + semantic search
-- "Find advice about hiring from product strategy episodes"
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

SELECT TOP 1 @query_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%hiring%' AND ec.chunk_text LIKE '%interview%';

SELECT TOP 10
    e.guest_name,
    e.episode_title,
    LEFT(ec.chunk_text, 300) AS chunk_preview,
    ec.start_timestamp,
    t.topic_name,
    VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
JOIN EpisodeTopics et ON e.episode_id = et.episode_id
JOIN Topics t ON et.topic_id = t.topic_id
WHERE t.topic_slug = 'hiring'
  AND ce.embedding IS NOT NULL
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 4: Explore topics and episodes
-- ============================================================================

-- Most covered topics
SELECT TOP 20
    t.topic_name,
    COUNT(et.episode_id) AS episode_count
FROM Topics t
JOIN EpisodeTopics et ON t.topic_id = et.topic_id
GROUP BY t.topic_id, t.topic_name
ORDER BY episode_count DESC;

-- Most viewed episodes
SELECT TOP 20
    guest_name,
    episode_title,
    publish_date,
    view_count,
    (SELECT COUNT(*) FROM EpisodeChunks ec WHERE ec.episode_id = e.episode_id) AS chunk_count
FROM Episodes e
WHERE view_count IS NOT NULL
ORDER BY view_count DESC;
GO

-- ============================================================================
-- QUERY 5: Full-text style keyword search (without FTS)
-- Find chunks mentioning specific terms
-- ============================================================================

SELECT TOP 20
    e.guest_name,
    e.episode_title,
    LEFT(ec.chunk_text, 300) AS chunk_preview,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link
FROM EpisodeChunks ec
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE ec.chunk_text LIKE '%product-market fit%'
ORDER BY e.publish_date DESC;
GO

-- ============================================================================
-- QUERY 6: Database statistics
-- ============================================================================

SELECT
    'Episodes' AS metric, COUNT(*) AS value FROM Episodes
UNION ALL
SELECT 'Episodes with chunks', COUNT(DISTINCT episode_id) FROM EpisodeChunks
UNION ALL
SELECT 'Total Q&A chunks', COUNT(*) FROM EpisodeChunks
UNION ALL
SELECT 'Chunks with embeddings', COUNT(*) FROM ChunkEmbeddings WHERE embedding IS NOT NULL
UNION ALL
SELECT 'Topics', COUNT(*) FROM Topics
UNION ALL
SELECT 'Episode-Topic mappings', COUNT(*) FROM EpisodeTopics
UNION ALL
SELECT 'Keywords', COUNT(*) FROM EpisodeKeywords;
GO
