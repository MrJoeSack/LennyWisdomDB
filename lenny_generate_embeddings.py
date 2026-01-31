"""
Generate embeddings for LennyWisdomDB chunks using Ollama batch API.
Designed to be run in parallel batches by chunk_id range.

Usage: python lenny_generate_embeddings.py <start_chunk_id> <end_chunk_id>
"""

import sys
import requests
import pyodbc
import json
import time

CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"
OLLAMA_URL = "http://localhost:11434/api/embed"
MODEL_NAME = "snowflake-arctic-embed2"
BATCH_SIZE = 50  # Texts per Ollama request
COMMIT_INTERVAL = 100  # Commit every N embeddings

def get_model_id(cursor) -> int:
    """Get the model_id for snowflake-arctic-embed2."""
    cursor.execute("SELECT model_id FROM EmbeddingModels WHERE model_name = ?", MODEL_NAME)
    row = cursor.fetchone()
    if not row:
        raise ValueError(f"Model {MODEL_NAME} not found in EmbeddingModels table")
    return row[0]

def generate_embeddings_batch(texts: list) -> list:
    """Generate embeddings for a batch of texts using Ollama batch API."""
    response = requests.post(OLLAMA_URL, json={
        "model": MODEL_NAME,
        "input": texts
    })
    response.raise_for_status()
    result = response.json()
    return result.get("embeddings", [])

def format_vector(embedding: list) -> str:
    """Format embedding list as SQL Server VECTOR string."""
    return "[" + ",".join(str(x) for x in embedding) + "]"

def process_chunk_range(start_id: int, end_id: int):
    """Process chunks in the given ID range."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    model_id = get_model_id(cursor)
    print(f"Using model_id: {model_id} for {MODEL_NAME}")

    # Get chunks that don't have embeddings yet
    cursor.execute("""
        SELECT ec.chunk_id, ec.chunk_text
        FROM EpisodeChunks ec
        LEFT JOIN ChunkEmbeddings ce ON ec.chunk_id = ce.chunk_id AND ce.model_id = ?
        WHERE ec.chunk_id BETWEEN ? AND ?
          AND ce.embedding_id IS NULL
        ORDER BY ec.chunk_id
    """, (model_id, start_id, end_id))

    chunks = cursor.fetchall()
    total = len(chunks)
    print(f"Found {total} chunks to embed in range {start_id}-{end_id}")

    if total == 0:
        print("No chunks to process")
        return

    processed = 0
    start_time = time.time()

    # Process in batches
    for i in range(0, total, BATCH_SIZE):
        batch = chunks[i:i + BATCH_SIZE]
        chunk_ids = [c[0] for c in batch]
        texts = [c[1] for c in batch]

        try:
            embeddings = generate_embeddings_batch(texts)

            for chunk_id, embedding in zip(chunk_ids, embeddings):
                vector_str = format_vector(embedding)
                # Cast through VARCHAR to avoid ntext-to-vector error
                sql = f"""
                    INSERT INTO ChunkEmbeddings (chunk_id, model_id, embedding)
                    VALUES ({chunk_id}, {model_id}, CAST(CAST('{vector_str}' AS VARCHAR(MAX)) AS VECTOR(1024)))
                """
                cursor.execute(sql)

            processed += len(batch)

            if processed % COMMIT_INTERVAL == 0 or processed == total:
                conn.commit()
                elapsed = time.time() - start_time
                rate = processed / elapsed if elapsed > 0 else 0
                print(f"  Processed {processed}/{total} ({rate:.1f}/sec)")

        except Exception as e:
            print(f"Error processing batch starting at chunk {chunk_ids[0]}: {e}")
            conn.rollback()
            # Try individual processing for failed batch
            for chunk_id, text in zip(chunk_ids, texts):
                try:
                    emb = generate_embeddings_batch([text])[0]
                    vector_str = format_vector(emb)
                    sql = f"""
                        INSERT INTO ChunkEmbeddings (chunk_id, model_id, embedding)
                        VALUES ({chunk_id}, {model_id}, CAST(CAST('{vector_str}' AS VARCHAR(MAX)) AS VECTOR(1024)))
                    """
                    cursor.execute(sql)
                    processed += 1
                except Exception as e2:
                    print(f"  Failed chunk {chunk_id}: {e2}")

    conn.commit()
    cursor.close()
    conn.close()

    elapsed = time.time() - start_time
    print(f"\nComplete: {processed} embeddings in {elapsed:.1f}s ({processed/elapsed:.1f}/sec)")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python lenny_generate_embeddings.py <start_chunk_id> <end_chunk_id>")
        sys.exit(1)

    start_id = int(sys.argv[1])
    end_id = int(sys.argv[2])
    process_chunk_range(start_id, end_id)
