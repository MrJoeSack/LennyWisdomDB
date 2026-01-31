"""
Embed search phrases using Ollama batch API.
Uses snowflake-arctic-embed2 to match chunk embeddings.
"""

import requests
import pyodbc

CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"
OLLAMA_URL = "http://localhost:11434/api/embed"
MODEL_NAME = "snowflake-arctic-embed2"

def generate_embeddings_batch(texts: list) -> list:
    """Generate embeddings for a batch of texts."""
    response = requests.post(OLLAMA_URL, json={
        "model": MODEL_NAME,
        "input": texts
    })
    response.raise_for_status()
    return response.json().get("embeddings", [])

def format_vector(embedding: list) -> str:
    """Format embedding as SQL Server VECTOR literal."""
    return "[" + ",".join(str(x) for x in embedding) + "]"

def embed_search_phrases():
    """Embed all search phrases that don't have vectors yet."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    # Get phrases without embeddings
    cursor.execute("""
        SELECT search_id, search_phrase
        FROM search_phrases
        WHERE search_vector IS NULL
        ORDER BY search_id
    """)
    phrases = cursor.fetchall()

    print(f"Found {len(phrases)} phrases to embed")

    if not phrases:
        print("All phrases already embedded")
        return

    # Embed all at once (small batch)
    ids = [p[0] for p in phrases]
    texts = [p[1] for p in phrases]

    print(f"Generating embeddings with {MODEL_NAME}...")
    embeddings = generate_embeddings_batch(texts)

    print(f"Updating database...")
    for search_id, embedding in zip(ids, embeddings):
        vector_str = format_vector(embedding)
        # Build full SQL statement to avoid identifier length limits
        sql = f"UPDATE search_phrases SET search_vector = CAST('{vector_str}' AS VECTOR(1024)) WHERE search_id = {search_id}"
        cursor.execute(sql)

    conn.commit()
    cursor.close()
    conn.close()

    print(f"Done: {len(embeddings)} phrases embedded")

if __name__ == "__main__":
    embed_search_phrases()
