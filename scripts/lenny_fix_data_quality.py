"""
LennyWisdomDB Data Quality Fixes

Addresses issues identified by quality audit:
1. Remove duplicate episodes (same video_id, keep originals)
2. Delete orphan episode 280 (Teaser_2021)
3. Fix episode 95 corruption (41 duplicate intro chunks)
4. Remove remaining sponsor content chunks
5. Fix encoding issues (Gustav Soderström)
6. Remove very short chunks (<30 chars, low semantic value)
7. Fix invalid video_id (episode 114)
"""

import pyodbc

CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"

def fix_duplicate_episodes(cursor):
    """Remove duplicate episodes (keep the original, delete '2.0' versions)."""
    print("\n=== Fixing Duplicate Episodes ===")

    # Find duplicates by video_id
    cursor.execute("""
        SELECT video_id, COUNT(*) as cnt
        FROM Episodes
        WHERE video_id IS NOT NULL
        GROUP BY video_id
        HAVING COUNT(*) > 1
    """)
    duplicates = cursor.fetchall()
    print(f"Found {len(duplicates)} duplicate video_ids")

    deleted_episodes = 0
    deleted_chunks = 0
    deleted_embeddings = 0

    for video_id, cnt in duplicates:
        # Get all episodes with this video_id
        cursor.execute("""
            SELECT episode_id, guest_name, folder_name
            FROM Episodes
            WHERE video_id = ?
            ORDER BY episode_id
        """, (video_id,))
        episodes = cursor.fetchall()

        # Keep the first one (original), delete the rest
        for episode_id, guest_name, folder_name in episodes[1:]:
            # Count what we're deleting
            cursor.execute("SELECT COUNT(*) FROM ChunkEmbeddings ce JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id WHERE ec.episode_id = ?", (episode_id,))
            emb_count = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM EpisodeChunks WHERE episode_id = ?", (episode_id,))
            chunk_count = cursor.fetchone()[0]

            # Delete in order: embeddings -> chunks -> topics -> keywords -> episode
            cursor.execute("DELETE ce FROM ChunkEmbeddings ce JOIN EpisodeChunks ec ON ce.chunk_id = ec.chunk_id WHERE ec.episode_id = ?", (episode_id,))
            cursor.execute("DELETE FROM EpisodeChunks WHERE episode_id = ?", (episode_id,))
            cursor.execute("DELETE FROM EpisodeTopics WHERE episode_id = ?", (episode_id,))
            cursor.execute("DELETE FROM EpisodeKeywords WHERE episode_id = ?", (episode_id,))
            cursor.execute("DELETE FROM Episodes WHERE episode_id = ?", (episode_id,))

            print(f"  Deleted episode {episode_id} ({guest_name}): {chunk_count} chunks, {emb_count} embeddings")
            deleted_episodes += 1
            deleted_chunks += chunk_count
            deleted_embeddings += emb_count

    print(f"Total: {deleted_episodes} duplicate episodes, {deleted_chunks} chunks, {deleted_embeddings} embeddings removed")
    return deleted_episodes

def fix_orphan_episode(cursor):
    """Delete episode 280 (Teaser_2021) which has no usable content."""
    print("\n=== Removing Orphan Episode 280 (Teaser_2021) ===")

    cursor.execute("SELECT episode_id, guest_name FROM Episodes WHERE episode_id = 280")
    row = cursor.fetchone()
    if row:
        cursor.execute("DELETE FROM EpisodeTopics WHERE episode_id = 280")
        cursor.execute("DELETE FROM EpisodeKeywords WHERE episode_id = 280")
        cursor.execute("DELETE FROM Episodes WHERE episode_id = 280")
        print(f"  Deleted episode 280 ({row[1]})")
        return 1
    else:
        print("  Episode 280 not found (already deleted?)")
        return 0

def fix_episode_95_corruption(cursor):
    """Fix episode 95 which has 41 duplicate intro chunks."""
    print("\n=== Fixing Episode 95 Corruption ===")

    # Episode 95 has chunks 1-41 that are all the same intro text split
    # Delete these and resequence
    cursor.execute("""
        SELECT chunk_id, chunk_sequence, LEFT(chunk_text, 50) as preview
        FROM EpisodeChunks
        WHERE episode_id = 95 AND chunk_sequence <= 41
        ORDER BY chunk_sequence
    """)
    intro_chunks = cursor.fetchall()

    if len(intro_chunks) > 0:
        # Check if they're really the duplicate intro
        cursor.execute("""
            SELECT COUNT(DISTINCT LEFT(chunk_text, 100))
            FROM EpisodeChunks
            WHERE episode_id = 95 AND chunk_sequence <= 41
        """)
        distinct_count = cursor.fetchone()[0]

        if distinct_count <= 5:  # All basically the same intro
            chunk_ids = [c[0] for c in intro_chunks]

            # Delete embeddings first
            cursor.execute(f"""
                DELETE FROM ChunkEmbeddings
                WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
            """)

            # Delete the corrupted chunks
            cursor.execute(f"""
                DELETE FROM EpisodeChunks
                WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
            """)

            # Resequence remaining chunks
            cursor.execute("""
                WITH Resequenced AS (
                    SELECT chunk_id, ROW_NUMBER() OVER (ORDER BY chunk_sequence) as new_seq
                    FROM EpisodeChunks
                    WHERE episode_id = 95
                )
                UPDATE ec
                SET chunk_sequence = r.new_seq
                FROM EpisodeChunks ec
                JOIN Resequenced r ON ec.chunk_id = r.chunk_id
            """)

            print(f"  Deleted {len(chunk_ids)} corrupted intro chunks from episode 95")
            return len(chunk_ids)

    print("  No corruption found in episode 95")
    return 0

def remove_sponsor_chunks(cursor):
    """Remove chunks that are primarily sponsor content."""
    print("\n=== Removing Sponsor Content Chunks ===")

    # Find chunks that are clearly sponsor segments
    cursor.execute("""
        SELECT ec.chunk_id, ec.episode_id, LEFT(ec.chunk_text, 100) as preview
        FROM EpisodeChunks ec
        WHERE (
            ec.chunk_text LIKE '%This episode is brought to you by%'
            OR ec.chunk_text LIKE '%Today''s sponsor%'
            OR ec.chunk_text LIKE '%brought to you by Vanta%'
            OR ec.chunk_text LIKE '%brought to you by Linear%'
            OR ec.chunk_text LIKE '%brought to you by Notion%'
            OR ec.chunk_text LIKE '%brought to you by Coda%'
            OR ec.chunk_text LIKE '%brought to you by Amplitude%'
        )
        AND LEN(ec.chunk_text) < 800  -- Short sponsor reads
    """)
    sponsor_chunks = cursor.fetchall()

    if sponsor_chunks:
        chunk_ids = [c[0] for c in sponsor_chunks]

        # Delete embeddings
        cursor.execute(f"""
            DELETE FROM ChunkEmbeddings
            WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
        """)

        # Delete chunks
        cursor.execute(f"""
            DELETE FROM EpisodeChunks
            WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
        """)

        print(f"  Deleted {len(chunk_ids)} sponsor content chunks")
        return len(chunk_ids)

    print("  No clear sponsor chunks found")
    return 0

def remove_tiny_chunks(cursor):
    """Remove chunks under 30 characters (minimal semantic value)."""
    print("\n=== Removing Very Short Chunks (<30 chars) ===")

    cursor.execute("""
        SELECT chunk_id, chunk_text
        FROM EpisodeChunks
        WHERE char_count < 30
    """)
    tiny_chunks = cursor.fetchall()

    if tiny_chunks:
        chunk_ids = [c[0] for c in tiny_chunks]

        # Delete embeddings
        cursor.execute(f"""
            DELETE FROM ChunkEmbeddings
            WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
        """)

        # Delete chunks
        cursor.execute(f"""
            DELETE FROM EpisodeChunks
            WHERE chunk_id IN ({','.join(str(x) for x in chunk_ids)})
        """)

        print(f"  Deleted {len(chunk_ids)} tiny chunks")
        # Show examples
        for cid, text in tiny_chunks[:5]:
            print(f"    Example: '{text}'")
        return len(chunk_ids)

    print("  No tiny chunks found")
    return 0

def fix_encoding_issues(cursor):
    """Fix known encoding issues in guest names."""
    print("\n=== Fixing Encoding Issues ===")

    # Fix Gustav Söderström
    cursor.execute("""
        UPDATE Episodes
        SET guest_name = 'Gustav Soderstrom'
        WHERE guest_name LIKE '%Gustav S%derstr%m%'
    """)
    if cursor.rowcount > 0:
        print(f"  Fixed {cursor.rowcount} encoding issues in guest names")
        return cursor.rowcount

    print("  No encoding issues found")
    return 0

def fix_invalid_video_id(cursor):
    """Fix episode 114 which has a slug instead of YouTube video ID."""
    print("\n=== Fixing Invalid Video ID ===")

    cursor.execute("""
        SELECT episode_id, guest_name, video_id
        FROM Episodes
        WHERE episode_id = 114
    """)
    row = cursor.fetchone()

    if row and row[2] == 'gokul-rajaram':
        # This is a slug, not a video ID - set to NULL
        cursor.execute("""
            UPDATE Episodes
            SET video_id = NULL, youtube_url = NULL
            WHERE episode_id = 114
        """)
        print(f"  Fixed episode 114 ({row[1]}): invalid video_id set to NULL")
        return 1

    print("  No invalid video_id found")
    return 0

def print_final_stats(cursor):
    """Print database stats after cleanup."""
    print("\n=== Final Database Stats ===")

    stats = [
        ("Episodes", "SELECT COUNT(*) FROM Episodes"),
        ("Episodes with chunks", "SELECT COUNT(DISTINCT episode_id) FROM EpisodeChunks"),
        ("Total Q&A chunks", "SELECT COUNT(*) FROM EpisodeChunks"),
        ("Chunks with embeddings", "SELECT COUNT(*) FROM ChunkEmbeddings WHERE embedding IS NOT NULL"),
        ("Topics", "SELECT COUNT(*) FROM Topics"),
        ("Episode-Topic mappings", "SELECT COUNT(*) FROM EpisodeTopics"),
    ]

    for name, query in stats:
        cursor.execute(query)
        count = cursor.fetchone()[0]
        print(f"  {name}: {count:,}")

def main():
    print("=" * 60)
    print("LennyWisdomDB Data Quality Fixes")
    print("=" * 60)

    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    try:
        # Run all fixes
        fix_duplicate_episodes(cursor)
        fix_orphan_episode(cursor)
        fix_episode_95_corruption(cursor)
        remove_sponsor_chunks(cursor)
        remove_tiny_chunks(cursor)
        fix_encoding_issues(cursor)
        fix_invalid_video_id(cursor)

        # Commit all changes
        conn.commit()
        print("\n*** All changes committed ***")

        # Print final stats
        print_final_stats(cursor)

    except Exception as e:
        print(f"\nError: {e}")
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()

    print("\n" + "=" * 60)
    print("Data quality fixes complete")
    print("=" * 60)

if __name__ == "__main__":
    main()
