/*
    LennyWisdomDB - SOTA Schema Migration

    Implements industry best practices for production RAG systems:
    - Parent-child chunk architecture (qa_group_id)
    - Hybrid search support (full-text + vector)
    - Enhanced embedding versioning
    - Token count tracking
    - Content type classification
    - Contextualized chunk storage (Anthropic pattern)
    - Search analytics / audit trail
    - Reranking score storage
    - Data lineage tracking

    Run this after restoring the base LennyWisdomDB backup.
*/

USE LennyWisdomDB;
GO

PRINT '=== LennyWisdomDB SOTA Migration ===';
PRINT '';

-- ============================================================================
-- 1. PARENT-CHILD CHUNK ARCHITECTURE
--    Links split chunks to their parent Q&A pair for deduplication
-- ============================================================================

PRINT '1. Adding qa_group_id for parent-child chunk linking...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EpisodeChunks') AND name = 'qa_group_id')
BEGIN
    ALTER TABLE EpisodeChunks ADD qa_group_id INT NULL;
END
GO

-- Populate qa_group_id: chunks with same episode + start_timestamp belong to same Q&A
-- For split chunks, the first part (split_part=1) defines the group
UPDATE ec
SET qa_group_id = grp.group_id
FROM EpisodeChunks ec
JOIN (
    SELECT
        chunk_id,
        DENSE_RANK() OVER (ORDER BY episode_id, start_seconds) AS group_id
    FROM EpisodeChunks
    WHERE split_part = 1
) grp ON ec.episode_id = (SELECT episode_id FROM EpisodeChunks WHERE chunk_id = grp.chunk_id)
     AND ec.start_seconds = (SELECT start_seconds FROM EpisodeChunks WHERE chunk_id = grp.chunk_id);
GO

-- For any remaining NULL qa_group_ids (split parts 2, 3, etc.), inherit from part 1
UPDATE ec_split
SET qa_group_id = ec_parent.qa_group_id
FROM EpisodeChunks ec_split
JOIN EpisodeChunks ec_parent
    ON ec_split.episode_id = ec_parent.episode_id
    AND ec_split.start_seconds = ec_parent.start_seconds
    AND ec_parent.split_part = 1
WHERE ec_split.qa_group_id IS NULL;
GO

-- Create index for efficient grouping
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EpisodeChunks_QAGroup')
    CREATE INDEX IX_EpisodeChunks_QAGroup ON EpisodeChunks(qa_group_id, split_part);
GO

PRINT '   Done. qa_group_id populated for all chunks.';
PRINT '';

-- ============================================================================
-- 2. TOKEN COUNT TRACKING
--    LLM context windows measured in tokens, not characters
-- ============================================================================

PRINT '2. Adding token_count column...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EpisodeChunks') AND name = 'token_count')
BEGIN
    ALTER TABLE EpisodeChunks ADD token_count INT NULL;
END
GO

-- Estimate tokens: ~4 characters per token for English text
UPDATE EpisodeChunks
SET token_count = CEILING(char_count / 4.0)
WHERE token_count IS NULL;
GO

PRINT '   Done. token_count estimated from char_count.';
PRINT '';

-- ============================================================================
-- 3. CONTENT TYPE CLASSIFICATION
--    Enables pre-filtering before vector search
-- ============================================================================

PRINT '3. Adding content_type column...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EpisodeChunks') AND name = 'content_type')
BEGIN
    ALTER TABLE EpisodeChunks ADD content_type NVARCHAR(20) DEFAULT 'main';
END
GO

-- Classify intro chunks (first 2 minutes typically intro)
UPDATE EpisodeChunks
SET content_type = 'intro'
WHERE start_seconds < 120 AND content_type IS NULL;

-- Main content is default
UPDATE EpisodeChunks
SET content_type = 'main'
WHERE content_type IS NULL;
GO

-- Create index for content type filtering
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EpisodeChunks_ContentType')
    CREATE INDEX IX_EpisodeChunks_ContentType ON EpisodeChunks(content_type);
GO

PRINT '   Done. content_type classified.';
PRINT '';

-- ============================================================================
-- 4. CONTEXTUALIZED CHUNK STORAGE (Anthropic Pattern)
--    Stores context-enriched text for better embedding quality
-- ============================================================================

PRINT '4. Adding contextualized_text column...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EpisodeChunks') AND name = 'contextualized_text')
BEGIN
    ALTER TABLE EpisodeChunks ADD contextualized_text NVARCHAR(MAX) NULL;
END
GO

-- Populate with episode context + chunk text
-- Format: "From [Episode Title] with [Guest]. [Question Speaker] asks about [topic]. [Answer Speaker] responds: [text]"
UPDATE ec
SET contextualized_text = CONCAT(
    'From Lenny''s Podcast with ', e.guest_name,
    ' (Episode: ', e.episode_title, '). ',
    CASE WHEN ec.speaker_question IS NOT NULL
         THEN CONCAT('Lenny asks: ', LEFT(ec.speaker_question, 200),
                     CASE WHEN LEN(ec.speaker_question) > 200 THEN '...' ELSE '' END, ' ')
         ELSE '' END,
    ec.answer_speaker, ' responds: ',
    ec.speaker_answer
)
FROM EpisodeChunks ec
JOIN Episodes e ON ec.episode_id = e.episode_id
WHERE ec.contextualized_text IS NULL;
GO

PRINT '   Done. contextualized_text populated.';
PRINT '';

-- ============================================================================
-- 5. ENHANCED EMBEDDING MODEL VERSIONING
-- ============================================================================

PRINT '5. Enhancing EmbeddingModels table...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EmbeddingModels') AND name = 'model_version')
BEGIN
    ALTER TABLE EmbeddingModels ADD model_version NVARCHAR(50) NULL;
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EmbeddingModels') AND name = 'embedding_norm')
BEGIN
    ALTER TABLE EmbeddingModels ADD embedding_norm NVARCHAR(20) NULL;
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('EmbeddingModels') AND name = 'notes')
BEGIN
    ALTER TABLE EmbeddingModels ADD notes NVARCHAR(500) NULL;
END
GO

-- Update existing model record
UPDATE EmbeddingModels
SET model_version = '1.0',
    embedding_norm = 'unit',
    notes = 'Snowflake Arctic Embed 2 via Ollama. 1024 dimensions, cosine similarity optimized.'
WHERE model_name = 'snowflake-arctic-embed2';
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 6. EMBEDDING GENERATION TIMESTAMP
-- ============================================================================

PRINT '6. Adding generated_date to ChunkEmbeddings...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('ChunkEmbeddings') AND name = 'generated_date')
BEGIN
    ALTER TABLE ChunkEmbeddings ADD generated_date DATETIME2 NULL;
END
GO

-- Set to created_date for existing records
UPDATE ChunkEmbeddings
SET generated_date = created_date
WHERE generated_date IS NULL;
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 7. DATA LINEAGE TRACKING
-- ============================================================================

PRINT '7. Adding data lineage columns to Episodes...';

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Episodes') AND name = 'source_file')
BEGIN
    ALTER TABLE Episodes ADD source_file NVARCHAR(500) NULL;
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Episodes') AND name = 'ingestion_date')
BEGIN
    ALTER TABLE Episodes ADD ingestion_date DATETIME2 NULL;
END

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('Episodes') AND name = 'ingestion_script')
BEGIN
    ALTER TABLE Episodes ADD ingestion_script NVARCHAR(100) NULL;
END
GO

-- Populate with known values
UPDATE Episodes
SET ingestion_script = 'lenny_chunk_qa.py',
    ingestion_date = created_date,
    source_file = CONCAT('transcripts/', folder_name, '/transcript.txt')
WHERE ingestion_date IS NULL;
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 8. SEARCH ANALYTICS / AUDIT TRAIL
-- ============================================================================

PRINT '8. Creating SearchLog table...';

IF OBJECT_ID('SearchLog', 'U') IS NULL
BEGIN
    CREATE TABLE SearchLog (
        search_id INT PRIMARY KEY IDENTITY(1,1),
        query_text NVARCHAR(500) NOT NULL,
        query_embedding VECTOR(1024) NULL,
        search_type NVARCHAR(20) DEFAULT 'vector',  -- 'vector', 'hybrid', 'fulltext'
        filter_episode_ids NVARCHAR(200) NULL,      -- JSON array if filtered
        filter_topics NVARCHAR(200) NULL,
        filter_content_type NVARCHAR(50) NULL,
        result_count INT NULL,
        execution_ms INT NULL,
        created_date DATETIME2 DEFAULT SYSDATETIME(),
        created_by NVARCHAR(100) NULL
    );

    CREATE INDEX IX_SearchLog_Date ON SearchLog(created_date);
    CREATE INDEX IX_SearchLog_Type ON SearchLog(search_type);
END
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 9. SEARCH RESULTS TRACKING (for reranking analysis)
-- ============================================================================

PRINT '9. Creating SearchResults table...';

IF OBJECT_ID('SearchResults', 'U') IS NULL
BEGIN
    CREATE TABLE SearchResults (
        result_id INT PRIMARY KEY IDENTITY(1,1),
        search_id INT NOT NULL,
        chunk_id INT NOT NULL,
        vector_rank INT NOT NULL,
        vector_distance DECIMAL(6,5) NOT NULL,
        bm25_rank INT NULL,                    -- Rank from full-text search
        bm25_score DECIMAL(10,4) NULL,
        rerank_score DECIMAL(6,5) NULL,        -- Cross-encoder reranker score
        final_rank INT NULL,
        rrf_score DECIMAL(6,5) NULL,           -- Reciprocal Rank Fusion score
        was_selected BIT DEFAULT 0,            -- User clicked/selected this result
        CONSTRAINT FK_Results_Search FOREIGN KEY (search_id) REFERENCES SearchLog(search_id),
        CONSTRAINT FK_Results_Chunk FOREIGN KEY (chunk_id) REFERENCES EpisodeChunks(chunk_id)
    );

    CREATE INDEX IX_SearchResults_Search ON SearchResults(search_id);
    CREATE INDEX IX_SearchResults_Chunk ON SearchResults(chunk_id);
END
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 10. HYBRID SEARCH SUPPORT (Full-Text Index)
-- ============================================================================

PRINT '10. Creating full-text catalog and index for hybrid search...';

-- Create full-text catalog if not exists
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = 'LennyFTCatalog')
BEGIN
    CREATE FULLTEXT CATALOG LennyFTCatalog AS DEFAULT;
END
GO

-- Need a unique index for full-text
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EpisodeChunks_ChunkID_Unique' AND object_id = OBJECT_ID('EpisodeChunks'))
BEGIN
    -- chunk_id is already PK, use that
    PRINT '   Using existing primary key for full-text index.';
END

-- Create full-text index on chunk_text
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID('EpisodeChunks'))
BEGIN
    CREATE FULLTEXT INDEX ON EpisodeChunks(chunk_text, speaker_question, speaker_answer)
        KEY INDEX PK__EpisodeC__3AAE37D8D7E8D4E3  -- Will need to get actual PK name
        ON LennyFTCatalog
        WITH CHANGE_TRACKING AUTO;
    PRINT '   Full-text index created.';
END
ELSE
BEGIN
    PRINT '   Full-text index already exists.';
END
GO

PRINT '';

-- ============================================================================
-- 11. UPDATE VIEWS FOR NEW COLUMNS
-- ============================================================================

PRINT '11. Updating views...';

-- Drop and recreate the search results view
IF OBJECT_ID('vw_ChunkSearchResults', 'V') IS NOT NULL
    DROP VIEW vw_ChunkSearchResults;
GO

CREATE VIEW vw_ChunkSearchResults AS
SELECT
    ce.embedding_id,
    ce.embedding,
    ec.chunk_id,
    ec.qa_group_id,
    ec.chunk_text,
    ec.contextualized_text,
    ec.speaker_question,
    ec.speaker_answer,
    ec.question_speaker,
    ec.answer_speaker,
    ec.start_timestamp,
    ec.start_seconds,
    ec.token_count,
    ec.content_type,
    ec.split_part,
    e.episode_id,
    e.guest_name,
    e.episode_title,
    e.youtube_url,
    e.video_id,
    e.publish_date,
    em.model_name,
    em.model_version
FROM ChunkEmbeddings ce
JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id
JOIN Episodes e ON ec.episode_id = e.episode_id
JOIN EmbeddingModels em ON ce.model_id = em.model_id
WHERE ce.embedding IS NOT NULL
  AND em.is_active = 1;
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- 12. CREATE HELPER PROCEDURES
-- ============================================================================

PRINT '12. Creating helper procedures...';

-- Procedure to log a search and return search_id
IF OBJECT_ID('usp_LogSearch', 'P') IS NOT NULL
    DROP PROCEDURE usp_LogSearch;
GO

CREATE PROCEDURE usp_LogSearch
    @query_text NVARCHAR(500),
    @query_embedding VECTOR(1024) = NULL,
    @search_type NVARCHAR(20) = 'vector',
    @search_id INT OUTPUT
AS
BEGIN
    INSERT INTO SearchLog (query_text, query_embedding, search_type)
    VALUES (@query_text, @query_embedding, @search_type);

    SET @search_id = SCOPE_IDENTITY();
END
GO

-- Procedure to update search with results
IF OBJECT_ID('usp_UpdateSearchResults', 'P') IS NOT NULL
    DROP PROCEDURE usp_UpdateSearchResults;
GO

CREATE PROCEDURE usp_UpdateSearchResults
    @search_id INT,
    @result_count INT,
    @execution_ms INT
AS
BEGIN
    UPDATE SearchLog
    SET result_count = @result_count,
        execution_ms = @execution_ms
    WHERE search_id = @search_id;
END
GO

PRINT '   Done.';
PRINT '';

-- ============================================================================
-- SUMMARY STATISTICS
-- ============================================================================

PRINT '=== Migration Complete ===';
PRINT '';

SELECT 'Chunks with qa_group_id' AS metric, COUNT(*) AS value
FROM EpisodeChunks WHERE qa_group_id IS NOT NULL
UNION ALL
SELECT 'Unique Q&A groups', COUNT(DISTINCT qa_group_id) FROM EpisodeChunks
UNION ALL
SELECT 'Chunks with token_count', COUNT(*) FROM EpisodeChunks WHERE token_count IS NOT NULL
UNION ALL
SELECT 'Chunks with contextualized_text', COUNT(*) FROM EpisodeChunks WHERE contextualized_text IS NOT NULL
UNION ALL
SELECT 'Intro content chunks', COUNT(*) FROM EpisodeChunks WHERE content_type = 'intro'
UNION ALL
SELECT 'Main content chunks', COUNT(*) FROM EpisodeChunks WHERE content_type = 'main';
GO

PRINT '';
PRINT 'New tables created: SearchLog, SearchResults';
PRINT 'New columns added: qa_group_id, token_count, content_type, contextualized_text';
PRINT 'Full-text catalog created: LennyFTCatalog';
PRINT '';
PRINT 'Run LennyWisdomDB_SOTA_Queries.sql for demo queries showcasing these features.';
GO
