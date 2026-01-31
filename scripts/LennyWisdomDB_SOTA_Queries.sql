/*
    LennyWisdomDB - SOTA Query Patterns

    Demonstrates production-grade RAG patterns:
    1. Parent Document Retrieval (dedupe by qa_group_id)
    2. Hybrid Search (Vector + BM25 with Reciprocal Rank Fusion)
    3. Pre-filtering by metadata
    4. Search audit logging
    5. Two-stage retrieval with reranking

    Prerequisites: Run LennyWisdomDB_SOTA_Migration.sql first
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- PATTERN 1: PARENT DOCUMENT RETRIEVAL
-- Best practice: retrieve by chunk, dedupe by Q&A group
-- Returns one result per unique Q&A pair, even if it was split into multiple chunks
-- ============================================================================

PRINT '=== Pattern 1: Parent Document Retrieval ===';

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'how to create a product vision that actually inspires the team';

-- Retrieve best chunk per Q&A group (eliminates duplicates from split chunks)
SELECT
    qa_group_id,
    guest_name,
    LEFT(speaker_question, 150) AS question,
    LEFT(speaker_answer, 300) AS answer,
    CONCAT('https://youtube.com/watch?v=', video_id, '&t=', start_seconds, 's') AS youtube_link,
    best_distance
FROM (
    SELECT
        ec.qa_group_id,
        e.guest_name,
        ec.speaker_question,
        ec.speaker_answer,
        e.video_id,
        ec.start_seconds,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS distance,
        MIN(CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)))
            OVER (PARTITION BY ec.qa_group_id) AS best_distance,
        ROW_NUMBER() OVER (PARTITION BY ec.qa_group_id
            ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding)) AS rn
    FROM ChunkEmbeddings ce
    JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN Episodes e ON ec.episode_id = e.episode_id
) ranked
WHERE rn = 1  -- Best chunk per Q&A group
ORDER BY best_distance
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
GO

-- ============================================================================
-- PATTERN 2: HYBRID SEARCH (Vector + Full-Text with RRF)
-- Combines semantic similarity with keyword matching
-- Reciprocal Rank Fusion merges rankings without score normalization
-- ============================================================================

PRINT '=== Pattern 2: Hybrid Search with Reciprocal Rank Fusion ===';

DECLARE @search_text NVARCHAR(200) = 'product market fit signals metrics';
DECLARE @query_embedding VECTOR(1024);

-- Get embedding for semantic search
SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'signs you have product market fit and how to find it';

-- RRF formula: score = SUM(1 / (k + rank)) where k=60 is standard
-- Higher RRF score = better combined ranking
WITH VectorResults AS (
    SELECT
        ec.chunk_id,
        ec.qa_group_id,
        ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding)) AS vector_rank,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS vector_distance
    FROM ChunkEmbeddings ce
    JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    WHERE ec.split_part = 1  -- Avoid duplicates
),
FullTextResults AS (
    SELECT
        ec.chunk_id,
        ec.qa_group_id,
        ROW_NUMBER() OVER (ORDER BY ft.[RANK] DESC) AS ft_rank,
        ft.[RANK] AS ft_score
    FROM EpisodeChunks ec
    INNER JOIN CONTAINSTABLE(EpisodeChunks, (chunk_text, speaker_answer), @search_text, 100) AS ft
        ON ec.chunk_id = ft.[KEY]
    WHERE ec.split_part = 1
),
CombinedRRF AS (
    SELECT
        COALESCE(v.chunk_id, f.chunk_id) AS chunk_id,
        COALESCE(v.qa_group_id, f.qa_group_id) AS qa_group_id,
        v.vector_rank,
        v.vector_distance,
        f.ft_rank,
        f.ft_score,
        -- RRF with k=60 (standard constant)
        COALESCE(1.0 / (60 + v.vector_rank), 0) +
        COALESCE(1.0 / (60 + f.ft_rank), 0) AS rrf_score
    FROM VectorResults v
    FULL OUTER JOIN FullTextResults f ON v.chunk_id = f.chunk_id
)
SELECT TOP 10
    c.qa_group_id,
    e.guest_name,
    LEFT(ec.speaker_question, 100) AS question,
    LEFT(ec.speaker_answer, 200) AS answer,
    c.vector_rank,
    c.vector_distance,
    c.ft_rank,
    CAST(c.rrf_score AS DECIMAL(6,5)) AS rrf_score
FROM CombinedRRF c
JOIN EpisodeChunks ec ON c.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
ORDER BY c.rrf_score DESC;
GO

-- ============================================================================
-- PATTERN 3: PRE-FILTERING BY METADATA
-- Filter before vector search for efficiency and relevance
-- ============================================================================

PRINT '=== Pattern 3: Pre-filtered Vector Search ===';

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'how AI is changing product management';

-- Filter by topic and content type BEFORE vector search
SELECT TOP 10
    e.guest_name,
    e.episode_title,
    ec.content_type,
    LEFT(ec.speaker_answer, 250) AS answer,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS distance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
JOIN EpisodeTopics et ON e.episode_id = et.episode_id
JOIN Topics t ON et.topic_id = t.topic_id
WHERE ec.content_type = 'main'           -- Skip intros
  AND ec.split_part = 1                  -- Skip duplicate splits
  AND t.topic_slug IN ('ai', 'product-management', 'technology')  -- Topic filter
  AND e.publish_date >= '2023-01-01'     -- Recent episodes only
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);
GO

-- ============================================================================
-- PATTERN 4: SEARCH WITH AUDIT LOGGING
-- Log searches for debugging, analytics, and compliance
-- ============================================================================

PRINT '=== Pattern 4: Audited Search ===';

DECLARE @query_text NVARCHAR(500) = 'building a long and meaningful career';
DECLARE @query_embedding VECTOR(1024);
DECLARE @search_id INT;
DECLARE @start_time DATETIME2 = SYSDATETIME();

-- Get embedding
SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'building a career that lasts decades';

-- Log the search
EXEC usp_LogSearch
    @query_text = @query_text,
    @query_embedding = @query_embedding,
    @search_type = 'vector',
    @search_id = @search_id OUTPUT;

-- Perform search
SELECT TOP 10
    ec.chunk_id,
    ec.qa_group_id,
    e.guest_name,
    LEFT(ec.speaker_answer, 200) AS answer,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS distance
INTO #results
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE ec.split_part = 1
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding);

-- Log results
INSERT INTO SearchResults (search_id, chunk_id, vector_rank, vector_distance)
SELECT
    @search_id,
    chunk_id,
    ROW_NUMBER() OVER (ORDER BY distance),
    distance
FROM #results;

-- Update search with execution stats
EXEC usp_UpdateSearchResults
    @search_id = @search_id,
    @result_count = 10,
    @execution_ms = NULL;  -- Would calculate from DATEDIFF

-- Return results
SELECT * FROM #results;
DROP TABLE #results;

-- Show the audit log
SELECT TOP 5 * FROM SearchLog ORDER BY search_id DESC;
GO

-- ============================================================================
-- PATTERN 5: TWO-STAGE RETRIEVAL (Retrieve then Rerank)
-- First stage: fast vector search for top-N candidates
-- Second stage: more expensive reranking for precision
-- (Reranking typically done by cross-encoder model - simulated here)
-- ============================================================================

PRINT '=== Pattern 5: Two-Stage Retrieval Pattern ===';

DECLARE @query_embedding VECTOR(1024);

SELECT @query_embedding = search_vector
FROM search_phrases
WHERE search_phrase = 'giving tough feedback without destroying the relationship';

-- Stage 1: Retrieve top 25 candidates with fast vector search
WITH Stage1_Candidates AS (
    SELECT TOP 25
        ec.chunk_id,
        ec.qa_group_id,
        e.guest_name,
        ec.speaker_question,
        ec.speaker_answer,
        e.video_id,
        ec.start_seconds,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding) AS DECIMAL(5,4)) AS vector_distance,
        ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding)) AS vector_rank
    FROM ChunkEmbeddings ce
    JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN Episodes e ON ec.episode_id = e.episode_id
    WHERE ec.split_part = 1
    ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @query_embedding)
),
-- Stage 2: Simulate reranking with keyword boost
-- (In production, this would call a cross-encoder model)
Stage2_Reranked AS (
    SELECT
        *,
        -- Simulate rerank score: boost if query keywords appear in answer
        CASE
            WHEN speaker_answer LIKE '%feedback%' AND speaker_answer LIKE '%relationship%' THEN vector_distance * 0.8
            WHEN speaker_answer LIKE '%feedback%' OR speaker_answer LIKE '%tough%' THEN vector_distance * 0.9
            ELSE vector_distance
        END AS simulated_rerank_score
    FROM Stage1_Candidates
)
SELECT TOP 10
    guest_name,
    LEFT(speaker_question, 100) AS question,
    LEFT(speaker_answer, 250) AS answer,
    CONCAT('https://youtube.com/watch?v=', video_id, '&t=', start_seconds, 's') AS youtube_link,
    vector_rank AS stage1_rank,
    vector_distance,
    CAST(simulated_rerank_score AS DECIMAL(5,4)) AS rerank_score,
    ROW_NUMBER() OVER (ORDER BY simulated_rerank_score) AS final_rank
FROM Stage2_Reranked
ORDER BY simulated_rerank_score;
GO

-- ============================================================================
-- PATTERN 6: CONTEXTUALIZED EMBEDDINGS COMPARISON
-- Shows how contextualized text differs from raw chunks
-- ============================================================================

PRINT '=== Pattern 6: Contextualized vs Raw Chunks ===';

-- Compare raw chunk_text vs contextualized_text
SELECT TOP 5
    chunk_id,
    LEFT(chunk_text, 200) AS raw_chunk,
    LEFT(contextualized_text, 300) AS contextualized_chunk,
    token_count,
    content_type
FROM EpisodeChunks
WHERE contextualized_text IS NOT NULL
ORDER BY chunk_id;
GO

-- ============================================================================
-- ANALYTICS: Search Pattern Insights
-- ============================================================================

PRINT '=== Search Analytics ===';

-- Most common search types
SELECT
    search_type,
    COUNT(*) AS search_count,
    AVG(result_count) AS avg_results,
    AVG(execution_ms) AS avg_ms
FROM SearchLog
GROUP BY search_type;

-- Most retrieved chunks (indicates high-value content)
SELECT TOP 10
    ec.chunk_id,
    e.guest_name,
    LEFT(ec.speaker_answer, 100) AS answer_preview,
    COUNT(*) AS times_retrieved
FROM SearchResults sr
JOIN EpisodeChunks ec ON sr.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
GROUP BY ec.chunk_id, e.guest_name, ec.speaker_answer
ORDER BY times_retrieved DESC;
GO

-- ============================================================================
-- SCHEMA OVERVIEW
-- ============================================================================

PRINT '=== SOTA Schema Overview ===';

SELECT 'Episodes' AS [table], COUNT(*) AS row_count FROM Episodes
UNION ALL SELECT 'EpisodeChunks', COUNT(*) FROM EpisodeChunks
UNION ALL SELECT 'ChunkEmbeddings', COUNT(*) FROM ChunkEmbeddings
UNION ALL SELECT 'Unique Q&A Groups', COUNT(DISTINCT qa_group_id) FROM EpisodeChunks
UNION ALL SELECT 'search_phrases', COUNT(*) FROM search_phrases
UNION ALL SELECT 'SearchLog', COUNT(*) FROM SearchLog
UNION ALL SELECT 'SearchResults', COUNT(*) FROM SearchResults;
GO
