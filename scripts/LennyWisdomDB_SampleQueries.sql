/*
    LennyWisdomDB - Sample Semantic Search Queries

    SQL Server 2025 Vector Search - RTM (non-preview) features only:
    - VECTOR(1024) data type for storing embeddings
    - VECTOR_DISTANCE('cosine', ...) for similarity search

    Uses pre-embedded search phrases (73 common PM questions) - no LIKE wildcards needed.

    At 21K chunks, brute-force VECTOR_DISTANCE search completes in ~75ms.
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- Browse available search phrases by category
-- ============================================================================

SELECT category, COUNT(*) as phrase_count
FROM search_phrases
GROUP BY category
ORDER BY phrase_count DESC;
GO

-- List phrases in a category
SELECT search_id, search_phrase
FROM search_phrases
WHERE category = 'strategy'
ORDER BY search_id;
GO

-- ============================================================================
-- QUERY 1: Semantic search - Product Market Fit
-- Uses pre-embedded phrase instead of LIKE wildcard
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

-- Get pre-computed embedding for this search phrase
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
GO

-- ============================================================================
-- QUERY 2: Strategy advice - Good vs Bad Strategy
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'what bad strategy looks like and how to avoid it';

SELECT TOP 10
    e.guest_name,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 300) AS guest_answers,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,3)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 3: AI and Product Management
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'how AI is changing product management';

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
GO

-- ============================================================================
-- QUERY 4: Filter by topic + semantic search
-- Career advice from leadership-focused episodes
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'how to get promoted from PM to senior PM';

SELECT TOP 10
    e.guest_name,
    e.episode_title,
    LEFT(ec.chunk_text, 300) AS chunk_preview,
    t.topic_name,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,3)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
JOIN EpisodeTopics et ON e.episode_id = et.episode_id
JOIN Topics t ON et.topic_id = t.topic_id
WHERE t.topic_slug IN ('career', 'leadership', 'product-management')
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 5: Search by phrase ID (programmatic access)
-- ============================================================================

-- List some phrase IDs
SELECT search_id, category, search_phrase
FROM search_phrases
WHERE category IN ('growth', 'execution')
ORDER BY category, search_id;
GO

-- Search using phrase ID directly
DECLARE @search_id INT = 31;  -- "what metrics actually matter for products"
DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_id = @search_id;

SELECT TOP 10
    e.guest_name,
    LEFT(ec.chunk_text, 250) AS chunk_preview,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,3)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 6: Hiring advice
-- ============================================================================

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'hiring PMs and what to look for';

SELECT TOP 10
    e.guest_name,
    LEFT(ec.speaker_question, 100) AS question,
    LEFT(ec.speaker_answer, 200) AS answer,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,3)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- QUERY 7: Explore topics and episodes
-- ============================================================================

-- Most covered topics
SELECT TOP 15
    t.topic_name,
    COUNT(et.episode_id) AS episode_count
FROM Topics t
JOIN EpisodeTopics et ON t.topic_id = et.topic_id
GROUP BY t.topic_id, t.topic_name
ORDER BY episode_count DESC;

-- Most viewed episodes
SELECT TOP 15
    guest_name,
    episode_title,
    publish_date,
    FORMAT(view_count, 'N0') AS views
FROM Episodes
WHERE view_count IS NOT NULL
ORDER BY view_count DESC;
GO

-- ============================================================================
-- QUERY 8: Database statistics
-- ============================================================================

SELECT 'Episodes' AS metric, COUNT(*) AS value FROM Episodes
UNION ALL SELECT 'Q&A Chunks', COUNT(*) FROM EpisodeChunks
UNION ALL SELECT 'Chunk Embeddings', COUNT(*) FROM ChunkEmbeddings
UNION ALL SELECT 'Search Phrases', COUNT(*) FROM search_phrases
UNION ALL SELECT 'Topics', COUNT(*) FROM Topics;
GO

-- ============================================================================
-- All search phrases (73 pre-embedded PM questions)
-- ============================================================================

SELECT search_id, category, search_phrase
FROM search_phrases
ORDER BY category, search_id;
GO
