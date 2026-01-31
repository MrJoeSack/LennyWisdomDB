/*
    LennyWisdomDB - Demo Queries

    SQL Server 2025 vector search examples using pre-embedded search phrases.
    Restore LennyWisdomDB.bak first, then run these queries.
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- 1. SEMANTIC SEARCH
-- Find answers by meaning, not keywords
-- ============================================================================

DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'signs you have product market fit and how to find it';

SELECT TOP 10
    e.guest_name,
    ec.speaker_question,
    ec.speaker_answer,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)) AS distance
FROM dbo.ChunkEmbeddings ce
JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
WHERE ec.split_part = 1
  AND LEN(ec.speaker_answer) > 100
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query);
GO

-- ============================================================================
-- 2. HYBRID SEARCH (Vector + Full-Text with RRF)
-- Combine semantic similarity with keyword matching
-- ============================================================================

DECLARE @search_text NVARCHAR(200) = '"product market fit" OR signals OR metrics';
DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'signs you have product market fit and how to find it';

WITH VectorResults AS (
    SELECT
        ec.chunk_id,
        ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query)) AS vector_rank
    FROM dbo.ChunkEmbeddings ce
    JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    WHERE ec.split_part = 1
),
FullTextResults AS (
    SELECT
        ec.chunk_id,
        ROW_NUMBER() OVER (ORDER BY ft.[RANK] DESC) AS ft_rank
    FROM dbo.EpisodeChunks ec
    INNER JOIN CONTAINSTABLE(dbo.EpisodeChunks, (chunk_text, speaker_answer), @search_text, 100) AS ft
        ON ec.chunk_id = ft.[KEY]
    WHERE ec.split_part = 1
),
Combined AS (
    SELECT
        COALESCE(v.chunk_id, f.chunk_id) AS chunk_id,
        -- Reciprocal Rank Fusion: score = 1/(k+rank), k=60
        COALESCE(1.0 / (60 + v.vector_rank), 0) +
        COALESCE(1.0 / (60 + f.ft_rank), 0) AS rrf_score
    FROM VectorResults v
    FULL OUTER JOIN FullTextResults f ON v.chunk_id = f.chunk_id
)
SELECT TOP 10
    e.guest_name,
    ec.speaker_question,
    ec.speaker_answer,
    CAST(c.rrf_score AS DECIMAL(6,5)) AS rrf_score
FROM Combined c
JOIN dbo.EpisodeChunks ec ON c.chunk_id = ec.chunk_id
JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
ORDER BY c.rrf_score DESC;
GO

-- ============================================================================
-- 3. FILTERED SEARCH
-- Narrow results by topic and date, then rank by vector distance
-- ============================================================================

DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'how AI is changing product management';

SELECT TOP 10
    e.guest_name,
    e.episode_title,
    ec.speaker_answer,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)) AS distance
FROM dbo.ChunkEmbeddings ce
JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
WHERE ec.content_type = 'main'
  AND ec.split_part = 1
  AND LEN(ec.speaker_answer) > 100
  AND e.publish_date >= '2023-01-01'
  AND EXISTS (
      SELECT 1 FROM dbo.EpisodeTopics et
      JOIN dbo.Topics t ON et.topic_id = t.topic_id
      WHERE et.episode_id = e.episode_id
        AND t.topic_slug IN ('ai', 'product-management', 'product-strategy')
  )
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query);
GO

-- ============================================================================
-- 4. PARENT DOCUMENT RETRIEVAL
-- Dedupe split chunks by returning best match per Q&A group
-- ============================================================================

DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'how to create a product vision that actually inspires the team';

SELECT
    qa_group_id,
    guest_name,
    speaker_question,
    speaker_answer,
    youtube_link,
    best_distance
FROM (
    SELECT
        ec.qa_group_id,
        e.guest_name,
        ec.speaker_question,
        ec.speaker_answer,
        CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)) AS distance,
        MIN(CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)))
            OVER (PARTITION BY ec.qa_group_id) AS best_distance,
        ROW_NUMBER() OVER (PARTITION BY ec.qa_group_id
            ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query)) AS rn
    FROM dbo.ChunkEmbeddings ce
    JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
    WHERE LEN(ec.speaker_answer) > 100
) ranked
WHERE rn = 1
ORDER BY best_distance
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
GO

-- ============================================================================
-- 5. COMPARE PERSPECTIVES
-- Get the top answer from each expert on a topic
-- ============================================================================

DECLARE @query VECTOR(1024);

SELECT @query = search_vector
FROM dbo.search_phrases
WHERE search_phrase = 'what bad strategy looks like and how to avoid it';

SELECT
    guest_name,
    speaker_question,
    speaker_answer,
    youtube_link,
    distance
FROM (
    SELECT
        e.guest_name,
        ec.speaker_question,
        ec.speaker_answer,
        CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query) AS DECIMAL(5,4)) AS distance,
        ROW_NUMBER() OVER (PARTITION BY e.episode_id
            ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query)) AS rn
    FROM dbo.ChunkEmbeddings ce
    JOIN dbo.EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN dbo.Episodes e ON ec.episode_id = e.episode_id
    WHERE ec.split_part = 1
      AND LEN(ec.speaker_answer) > 100
) ranked
WHERE rn = 1
ORDER BY distance
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
GO
