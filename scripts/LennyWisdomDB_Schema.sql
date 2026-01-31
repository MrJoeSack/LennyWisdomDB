/*
    LennyWisdomDB - Schema Creation Script

    A SQL Server 2025 vector search sample database built from Lenny's Podcast transcripts.
    Implements production-grade RAG patterns including:
    - Parent-child chunk architecture for deduplication
    - Hybrid search support (vector + full-text)
    - Contextualized embeddings (Anthropic pattern)
    - Search audit logging
    - Embedding model versioning

    Prerequisites:
    - SQL Server 2025 with VECTOR data type support
*/

-- Create database
IF DB_ID('LennyWisdomDB') IS NOT NULL
BEGIN
    ALTER DATABASE LennyWisdomDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE LennyWisdomDB;
END
GO

CREATE DATABASE LennyWisdomDB;
GO

USE LennyWisdomDB;
GO

-- ============================================================================
-- EmbeddingModels - Track embedding model provenance with versioning
-- ============================================================================
CREATE TABLE EmbeddingModels (
    model_id INT PRIMARY KEY IDENTITY(1,1),
    model_name NVARCHAR(100) NOT NULL,
    model_version NVARCHAR(50) NULL,
    dimensions INT NOT NULL,
    provider NVARCHAR(50) NOT NULL,
    max_tokens INT NULL,
    embedding_norm NVARCHAR(20) NULL,           -- 'unit', 'unnormalized'
    notes NVARCHAR(500) NULL,
    deployed_date DATETIME2 DEFAULT SYSDATETIME(),
    is_active BIT DEFAULT 1,
    CONSTRAINT UQ_ModelName UNIQUE (model_name)
);

-- Insert the model used for this database
INSERT INTO EmbeddingModels (model_name, model_version, dimensions, provider, max_tokens, embedding_norm, notes, is_active)
VALUES ('snowflake-arctic-embed2', '1.0', 1024, 'Ollama', 8192, 'unit',
        'Snowflake Arctic Embed 2 via Ollama. 1024 dimensions, cosine similarity optimized.', 1);
GO

-- ============================================================================
-- Topics - Categories from Lenny's topic index
-- ============================================================================
CREATE TABLE Topics (
    topic_id INT PRIMARY KEY IDENTITY(1,1),
    topic_name NVARCHAR(100) NOT NULL,
    topic_slug NVARCHAR(100) NOT NULL,
    CONSTRAINT UQ_TopicSlug UNIQUE (topic_slug)
);
GO

-- ============================================================================
-- Episodes - Podcast episode metadata with data lineage
-- ============================================================================
CREATE TABLE Episodes (
    episode_id INT PRIMARY KEY IDENTITY(1,1),
    guest_name NVARCHAR(200) NOT NULL,
    episode_title NVARCHAR(500) NOT NULL,
    youtube_url NVARCHAR(500) NULL,
    video_id NVARCHAR(50) NULL,
    publish_date DATE NULL,
    duration_seconds INT NULL,
    duration_display NVARCHAR(20) NULL,
    view_count INT NULL,
    description NVARCHAR(MAX) NULL,
    folder_name NVARCHAR(200) NOT NULL,
    full_transcript NVARCHAR(MAX) NULL,
    -- Data lineage columns
    source_file NVARCHAR(500) NULL,
    ingestion_date DATETIME2 NULL,
    ingestion_script NVARCHAR(100) NULL,
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT UQ_FolderName UNIQUE (folder_name)
);
GO

-- ============================================================================
-- EpisodeTopics - Many-to-many mapping
-- ============================================================================
CREATE TABLE EpisodeTopics (
    episode_id INT NOT NULL,
    topic_id INT NOT NULL,
    CONSTRAINT PK_EpisodeTopics PRIMARY KEY (episode_id, topic_id),
    CONSTRAINT FK_EpisodeTopics_Episode FOREIGN KEY (episode_id) REFERENCES Episodes(episode_id),
    CONSTRAINT FK_EpisodeTopics_Topic FOREIGN KEY (topic_id) REFERENCES Topics(topic_id)
);
GO

-- ============================================================================
-- EpisodeKeywords - Keywords from YAML frontmatter
-- ============================================================================
CREATE TABLE EpisodeKeywords (
    episode_id INT NOT NULL,
    keyword NVARCHAR(100) NOT NULL,
    CONSTRAINT PK_EpisodeKeywords PRIMARY KEY (episode_id, keyword),
    CONSTRAINT FK_EpisodeKeywords_Episode FOREIGN KEY (episode_id) REFERENCES Episodes(episode_id)
);
GO

-- ============================================================================
-- EpisodeChunks - Q&A pairs with SOTA RAG columns
-- ============================================================================
CREATE TABLE EpisodeChunks (
    chunk_id INT PRIMARY KEY IDENTITY(1,1),
    episode_id INT NOT NULL,
    chunk_sequence INT NOT NULL,
    -- Q&A content
    speaker_question NVARCHAR(MAX) NULL,        -- Lenny's question (context)
    speaker_answer NVARCHAR(MAX) NULL,          -- Guest's answer
    chunk_text NVARCHAR(MAX) NOT NULL,          -- Combined text for embedding
    contextualized_text NVARCHAR(MAX) NULL,     -- Context-enriched text (Anthropic pattern)
    question_speaker NVARCHAR(200) NULL,        -- Usually 'Lenny'
    answer_speaker NVARCHAR(200) NULL,          -- Guest name
    -- Timestamps for YouTube deep-linking
    start_timestamp NVARCHAR(20) NULL,          -- HH:MM:SS format
    end_timestamp NVARCHAR(20) NULL,
    start_seconds INT NULL,
    -- Chunk metadata
    char_count INT NOT NULL,
    token_count INT NULL,                       -- Estimated tokens (~chars/4)
    content_type NVARCHAR(20) DEFAULT 'main',   -- 'intro', 'main', 'outro'
    -- Split chunk handling (parent-child architecture)
    is_split BIT DEFAULT 0,
    split_part INT DEFAULT 1,                   -- 1, 2, 3... if split
    qa_group_id INT NULL,                       -- Groups split chunks to same Q&A
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Chunks_Episode FOREIGN KEY (episode_id) REFERENCES Episodes(episode_id),
    CONSTRAINT UQ_ChunkSequence UNIQUE (episode_id, chunk_sequence)
);

-- Indexes for common query patterns
CREATE INDEX IX_EpisodeChunks_QAGroup ON EpisodeChunks(qa_group_id, split_part);
CREATE INDEX IX_EpisodeChunks_ContentType ON EpisodeChunks(content_type);
CREATE INDEX IX_EpisodeChunks_Episode ON EpisodeChunks(episode_id);
GO

-- ============================================================================
-- ChunkEmbeddings - Normalized embedding storage with generation tracking
-- ============================================================================
CREATE TABLE ChunkEmbeddings (
    embedding_id INT PRIMARY KEY IDENTITY(1,1),
    chunk_id INT NOT NULL,
    model_id INT NOT NULL,
    embedding VECTOR(1024) NULL,                -- NULL while pending generation
    generated_date DATETIME2 NULL,              -- When embedding was created
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Embeddings_Chunk FOREIGN KEY (chunk_id) REFERENCES EpisodeChunks(chunk_id),
    CONSTRAINT FK_Embeddings_Model FOREIGN KEY (model_id) REFERENCES EmbeddingModels(model_id),
    CONSTRAINT UQ_Chunk_Model UNIQUE (chunk_id, model_id)
);
GO

-- ============================================================================
-- search_phrases - Pre-embedded queries for instant semantic search
-- ============================================================================
CREATE TABLE search_phrases (
    search_id INT PRIMARY KEY IDENTITY(1,1),
    search_phrase NVARCHAR(500) NOT NULL,
    search_vector VECTOR(1024) NULL,
    category NVARCHAR(50) NULL,
    created_date DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- ============================================================================
-- SearchLog - Audit trail for search queries
-- ============================================================================
CREATE TABLE SearchLog (
    search_id INT PRIMARY KEY IDENTITY(1,1),
    query_text NVARCHAR(500) NOT NULL,
    query_embedding VECTOR(1024) NULL,
    search_type NVARCHAR(20) DEFAULT 'vector',  -- 'vector', 'hybrid', 'fulltext'
    filter_episode_ids NVARCHAR(200) NULL,
    filter_topics NVARCHAR(200) NULL,
    filter_content_type NVARCHAR(50) NULL,
    result_count INT NULL,
    execution_ms INT NULL,
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    created_by NVARCHAR(100) NULL
);

CREATE INDEX IX_SearchLog_Date ON SearchLog(created_date);
CREATE INDEX IX_SearchLog_Type ON SearchLog(search_type);
GO

-- ============================================================================
-- SearchResults - Track retrieved results for analytics
-- ============================================================================
CREATE TABLE SearchResults (
    result_id INT PRIMARY KEY IDENTITY(1,1),
    search_id INT NOT NULL,
    chunk_id INT NOT NULL,
    vector_rank INT NOT NULL,
    vector_distance DECIMAL(6,5) NOT NULL,
    bm25_rank INT NULL,
    bm25_score DECIMAL(10,4) NULL,
    rerank_score DECIMAL(6,5) NULL,
    final_rank INT NULL,
    rrf_score DECIMAL(6,5) NULL,
    was_selected BIT DEFAULT 0,
    CONSTRAINT FK_Results_Search FOREIGN KEY (search_id) REFERENCES SearchLog(search_id),
    CONSTRAINT FK_Results_Chunk FOREIGN KEY (chunk_id) REFERENCES EpisodeChunks(chunk_id)
);

CREATE INDEX IX_SearchResults_Search ON SearchResults(search_id);
CREATE INDEX IX_SearchResults_Chunk ON SearchResults(chunk_id);
GO

-- ============================================================================
-- Full-Text Catalog for Hybrid Search
-- ============================================================================
CREATE FULLTEXT CATALOG LennyFTCatalog AS DEFAULT;
GO

-- ============================================================================
-- Views for convenient querying
-- ============================================================================
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

CREATE VIEW vw_EpisodeSummary AS
SELECT
    e.episode_id,
    e.guest_name,
    e.episode_title,
    e.publish_date,
    e.duration_display,
    e.view_count,
    (SELECT COUNT(*) FROM EpisodeChunks ec WHERE ec.episode_id = e.episode_id) AS chunk_count,
    (SELECT COUNT(DISTINCT qa_group_id) FROM EpisodeChunks ec WHERE ec.episode_id = e.episode_id) AS qa_count,
    (SELECT COUNT(*) FROM EpisodeTopics et WHERE et.episode_id = e.episode_id) AS topic_count
FROM Episodes e;
GO

-- ============================================================================
-- Helper Procedures
-- ============================================================================
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

PRINT 'LennyWisdomDB schema created successfully.';
PRINT 'Use the .bak file to restore the database with data and embeddings.';
GO
