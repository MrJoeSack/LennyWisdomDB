/*
    LennyWisdomDB - Favorite Episodes Demo

    SQL Server 2025 Vector Search using RTM (non-preview) features only:
    - VECTOR(1024) data type for storing embeddings
    - VECTOR_DISTANCE('cosine', ...) for similarity search

    At 24K chunks, brute-force vector search completes in ~75ms.
    No DiskANN index needed at this scale.

    Focused semantic search demos using favorite Lenny's Podcast episodes:

    Episode 83:  Ebi Atawodi (YouTube, Netflix, Uber) - Product Vision
    Episode 218: Mike Krieger (Anthropic CPO, Instagram co-founder) - AI Products
    Episode 230: Nikhyl Singhal (Meta VP Product) - Career Building
    Episode 252: Richard Rumelt - Good Strategy, Bad Strategy
    Episode 270: Shaun Clowes (Confluent CPO) - AI & Data

    Note: GitLab (David DeSanto) and Tal Raviv episodes not in current transcript dump.
*/

USE LennyWisdomDB;
GO

-- ============================================================================
-- SETUP: Create a view for the favorite episodes
-- ============================================================================

IF OBJECT_ID('vw_FavoriteEpisodes', 'V') IS NOT NULL
    DROP VIEW vw_FavoriteEpisodes;
GO

CREATE VIEW vw_FavoriteEpisodes AS
SELECT
    e.episode_id,
    e.guest_name,
    e.episode_title,
    e.video_id,
    e.publish_date,
    e.view_count,
    (SELECT COUNT(*) FROM EpisodeChunks ec WHERE ec.episode_id = e.episode_id) AS chunk_count
FROM Episodes e
WHERE e.episode_id IN (83, 218, 230, 252, 270);  -- Ebi, Mike Krieger, Nikhyl, Rumelt, Shaun
GO

-- View the favorite episodes
SELECT * FROM vw_FavoriteEpisodes ORDER BY publish_date;
GO

-- ============================================================================
-- DEMO 1: Ebi Atawodi - Product Vision Framework
-- "How do I craft a compelling product vision?"
-- ============================================================================

PRINT '=== DEMO 1: Product Vision (Ebi Atawodi) ===';

DECLARE @vision_embedding VECTOR(1024);

-- Grab embedding from a vision-related chunk in Ebi's episode
SELECT TOP 1 @vision_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.episode_id = 83  -- Ebi Atawodi
  AND (ec.chunk_text LIKE '%vision%' OR ec.chunk_text LIKE '%strategy%');

-- Find the most relevant Q&A pairs about product vision
SELECT TOP 5
    'Ebi Atawodi' AS expert,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 400) AS ebi_answers,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS jump_to_clip,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @vision_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id = 83
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @vision_embedding);
GO

-- ============================================================================
-- DEMO 2: Mike Krieger (Anthropic) - Building AI Products
-- "What does the future of AI products look like?"
-- ============================================================================

PRINT '=== DEMO 2: AI Product Development (Mike Krieger - Anthropic CPO) ===';

DECLARE @ai_embedding VECTOR(1024);

-- Grab embedding from an AI-focused chunk
SELECT TOP 1 @ai_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.episode_id = 218  -- Mike Krieger
  AND (ec.chunk_text LIKE '%AI%' OR ec.chunk_text LIKE '%Claude%' OR ec.chunk_text LIKE '%model%');

SELECT TOP 5
    'Mike Krieger (Anthropic)' AS expert,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 400) AS mike_answers,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS jump_to_clip,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @ai_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id = 218
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @ai_embedding);
GO

-- ============================================================================
-- DEMO 3: Nikhyl Singhal - Building a Long Career
-- "How do I build a meaningful PM career?"
-- ============================================================================

PRINT '=== DEMO 3: Career Building (Nikhyl Singhal - Meta VP) ===';

DECLARE @career_embedding VECTOR(1024);

SELECT TOP 1 @career_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.episode_id = 230  -- Nikhyl Singhal
  AND (ec.chunk_text LIKE '%career%' OR ec.chunk_text LIKE '%growth%' OR ec.chunk_text LIKE '%job%');

SELECT TOP 5
    'Nikhyl Singhal (Meta)' AS expert,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 400) AS nikhyl_answers,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS jump_to_clip,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @career_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id = 230
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @career_embedding);
GO

-- ============================================================================
-- DEMO 4: Richard Rumelt - Good Strategy, Bad Strategy
-- "What makes a strategy good vs bad?"
-- ============================================================================

PRINT '=== DEMO 4: Good Strategy (Richard Rumelt) ===';

DECLARE @strategy_embedding VECTOR(1024);

SELECT TOP 1 @strategy_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.episode_id = 252  -- Richard Rumelt
  AND (ec.chunk_text LIKE '%strategy%' OR ec.chunk_text LIKE '%diagnosis%' OR ec.chunk_text LIKE '%kernel%');

SELECT TOP 5
    'Richard Rumelt' AS expert,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 400) AS rumelt_answers,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS jump_to_clip,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @strategy_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id = 252
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @strategy_embedding);
GO

-- ============================================================================
-- DEMO 5: Shaun Clowes - AI & Data Strategy
-- "Why is data so important for AI products?"
-- ============================================================================

PRINT '=== DEMO 4: AI & Data (Shaun Clowes - Confluent CPO) ===';

DECLARE @data_embedding VECTOR(1024);

SELECT TOP 1 @data_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.episode_id = 270  -- Shaun Clowes
  AND (ec.chunk_text LIKE '%data%' OR ec.chunk_text LIKE '%AI%');

SELECT TOP 5
    'Shaun Clowes (Confluent)' AS expert,
    LEFT(ec.speaker_question, 150) AS lenny_asks,
    LEFT(ec.speaker_answer, 400) AS shaun_answers,
    ec.start_timestamp,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS jump_to_clip,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @data_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id = 270
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @data_embedding);
GO

-- ============================================================================
-- DEMO 5: Cross-Episode Semantic Search
-- "Find the best advice about leadership across all favorite episodes"
-- ============================================================================

PRINT '=== DEMO 5: Cross-Episode Search - Leadership Advice ===';

DECLARE @leadership_embedding VECTOR(1024);

-- Borrow an embedding about leadership/management
SELECT TOP 1 @leadership_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%leader%' AND ec.chunk_text LIKE '%team%';

SELECT TOP 10
    e.guest_name AS expert,
    LEFT(ec.speaker_question, 120) AS question,
    LEFT(ec.speaker_answer, 300) AS answer,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
    CAST(VECTOR_DISTANCE('cosine', ce.embedding, @leadership_embedding) AS DECIMAL(5,3)) AS relevance
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id IN (83, 218, 230, 252, 270)  -- Favorite episodes
ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @leadership_embedding);
GO

-- ============================================================================
-- DEMO 6: Compare Perspectives - "What makes a great product?"
-- ============================================================================

PRINT '=== DEMO 6: Multiple Perspectives - Great Products ===';

DECLARE @product_embedding VECTOR(1024);

SELECT TOP 1 @product_embedding = ce.embedding
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
WHERE ec.chunk_text LIKE '%great product%' OR ec.chunk_text LIKE '%product excellence%';

-- Get top answer from each expert
SELECT expert, question, answer, youtube_link, relevance
FROM (
    SELECT
        e.guest_name AS expert,
        LEFT(ec.speaker_question, 100) AS question,
        LEFT(ec.speaker_answer, 250) AS answer,
        CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link,
        CAST(VECTOR_DISTANCE('cosine', ce.embedding, @product_embedding) AS DECIMAL(5,3)) AS relevance,
        ROW_NUMBER() OVER (PARTITION BY e.episode_id ORDER BY VECTOR_DISTANCE('cosine', ce.embedding, @product_embedding)) AS rn
    FROM ChunkEmbeddings ce
    JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
    JOIN Episodes e ON ec.episode_id = e.episode_id
    WHERE e.episode_id IN (83, 218, 230, 270)
) ranked
WHERE rn = 1
ORDER BY relevance;
GO

-- ============================================================================
-- DEMO 7: Topic Explorer - What topics do these experts cover?
-- ============================================================================

PRINT '=== DEMO 7: Topic Coverage Across Favorite Episodes ===';

SELECT
    e.guest_name,
    STRING_AGG(t.topic_name, ', ') WITHIN GROUP (ORDER BY t.topic_name) AS topics
FROM Episodes e
JOIN EpisodeTopics et ON e.episode_id = et.episode_id
JOIN Topics t ON et.topic_id = t.topic_id
WHERE e.episode_id IN (83, 218, 230, 270)
GROUP BY e.episode_id, e.guest_name
ORDER BY e.episode_id;
GO

-- ============================================================================
-- DEMO 8: Keyword Search - Find specific mentions
-- ============================================================================

PRINT '=== DEMO 8: Keyword Mentions in Favorite Episodes ===';

-- What do these experts say about "metrics"?
SELECT
    e.guest_name,
    LEFT(ec.chunk_text, 300) AS context,
    CONCAT('https://youtube.com/watch?v=', e.video_id, '&t=', ec.start_seconds, 's') AS youtube_link
FROM EpisodeChunks ec
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE e.episode_id IN (83, 218, 230, 270)
  AND ec.chunk_text LIKE '%metric%'
ORDER BY e.episode_id;
GO

-- ============================================================================
-- STATS: Favorite episodes summary
-- ============================================================================

PRINT '=== Favorite Episodes Summary ===';

SELECT
    e.guest_name,
    e.episode_title,
    e.publish_date,
    FORMAT(e.view_count, 'N0') AS views,
    COUNT(ec.chunk_id) AS qa_pairs,
    CONCAT('https://youtube.com/watch?v=', e.video_id) AS full_episode
FROM Episodes e
JOIN EpisodeChunks ec ON e.episode_id = ec.episode_id
WHERE e.episode_id IN (83, 218, 230, 270)
GROUP BY e.episode_id, e.guest_name, e.episode_title, e.publish_date, e.view_count, e.video_id
ORDER BY e.publish_date;
GO
