/*
    LennyWisdomDB - Schema Creation Script

    A SQL Server 2025 vector search sample database built from Lenny's Podcast transcripts.
    Contains 21,571 Q&A chunks with embeddings for semantic search.

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
-- EmbeddingModels - Track embedding model provenance (Module 03 pattern)
-- ============================================================================
CREATE TABLE EmbeddingModels (
    model_id INT PRIMARY KEY IDENTITY(1,1),
    model_name NVARCHAR(100) NOT NULL,
    dimensions INT NOT NULL,
    provider NVARCHAR(50) NOT NULL,
    max_tokens INT NULL,
    deployed_date DATETIME2 DEFAULT SYSDATETIME(),
    is_active BIT DEFAULT 1,
    CONSTRAINT UQ_ModelName UNIQUE (model_name)
);

-- Insert the model used for this database
INSERT INTO EmbeddingModels (model_name, dimensions, provider, max_tokens, is_active)
VALUES ('snowflake-arctic-embed2', 1024, 'Ollama', 8192, 1);
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
-- Episodes - Podcast episode metadata
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
-- EpisodeChunks - Q&A pairs with timestamps (semantic chunking)
-- ============================================================================
CREATE TABLE EpisodeChunks (
    chunk_id INT PRIMARY KEY IDENTITY(1,1),
    episode_id INT NOT NULL,
    chunk_sequence INT NOT NULL,
    speaker_question NVARCHAR(MAX) NULL,      -- Lenny's question (context)
    speaker_answer NVARCHAR(MAX) NULL,        -- Guest's answer
    chunk_text NVARCHAR(MAX) NOT NULL,        -- Combined text for embedding
    question_speaker NVARCHAR(200) NULL,      -- Usually 'Lenny'
    answer_speaker NVARCHAR(200) NULL,        -- Guest name
    start_timestamp NVARCHAR(20) NULL,        -- HH:MM:SS for YouTube linking
    end_timestamp NVARCHAR(20) NULL,
    start_seconds INT NULL,                   -- For easy YouTube URL building
    char_count INT NOT NULL,
    is_split BIT DEFAULT 0,                   -- True if answer was too long
    split_part INT DEFAULT 1,                 -- 1, 2, 3... if split
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Chunks_Episode FOREIGN KEY (episode_id) REFERENCES Episodes(episode_id),
    CONSTRAINT UQ_ChunkSequence UNIQUE (episode_id, chunk_sequence)
);
GO

-- ============================================================================
-- ChunkEmbeddings - Normalized embedding storage (Module 03 pattern)
-- ============================================================================
CREATE TABLE ChunkEmbeddings (
    embedding_id INT PRIMARY KEY IDENTITY(1,1),
    chunk_id INT NOT NULL,
    model_id INT NOT NULL,
    embedding VECTOR(1024) NULL,              -- NULL while pending generation
    created_date DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Embeddings_Chunk FOREIGN KEY (chunk_id) REFERENCES EpisodeChunks(chunk_id),
    CONSTRAINT FK_Embeddings_Model FOREIGN KEY (model_id) REFERENCES EmbeddingModels(model_id),
    CONSTRAINT UQ_Chunk_Model UNIQUE (chunk_id, model_id)
);
GO

-- ============================================================================
-- search_phrases - Pre-embedded PM questions for instant search
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
-- Views for convenient querying
-- ============================================================================
CREATE VIEW vw_ChunkSearchResults AS
SELECT
    ce.embedding_id,
    ce.embedding,
    ec.chunk_id,
    ec.chunk_text,
    ec.speaker_question,
    ec.speaker_answer,
    ec.question_speaker,
    ec.answer_speaker,
    ec.start_timestamp,
    ec.start_seconds,
    e.episode_id,
    e.guest_name,
    e.episode_title,
    e.youtube_url,
    e.video_id,
    e.publish_date,
    em.model_name
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
    (SELECT COUNT(*) FROM EpisodeTopics et WHERE et.episode_id = e.episode_id) AS topic_count
FROM Episodes e;
GO

PRINT 'LennyWisdomDB schema created successfully.';
PRINT 'Use the .bak file to restore the database with data and embeddings.';
GO
