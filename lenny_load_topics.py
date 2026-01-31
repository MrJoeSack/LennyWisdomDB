"""
Load topics from the index directory into LennyWisdomDB.
Maps episodes to topics based on the index files.
"""

import os
import re
import pyodbc
from pathlib import Path

INDEX_DIR = r"D:\Dropbox\Github\lennys-podcast-transcripts\index"
CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"

def parse_topic_file(topic_path: Path) -> dict:
    """Parse a topic index file and extract episode references."""
    with open(topic_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Topic name from first heading
    name_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
    topic_name = name_match.group(1).strip() if name_match else topic_path.stem.replace('-', ' ').title()

    # Extract episode folder names from links
    # Format: [Guest Name](../episodes/folder-name/transcript.md)
    episode_links = re.findall(r'\.\./episodes/([^/]+)/transcript\.md', content)

    return {
        'topic_slug': topic_path.stem,
        'topic_name': topic_name,
        'episodes': episode_links
    }

def load_topics():
    """Load all topics and map to episodes."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    # Get list of topic files
    index_path = Path(INDEX_DIR)
    topic_files = sorted([f for f in index_path.glob('*.md') if f.name not in ['README.md', 'episodes.md']])

    print(f"Found {len(topic_files)} topic files")

    # Build episode folder -> id lookup
    cursor.execute("SELECT episode_id, folder_name FROM Episodes")
    episode_lookup = {row[1]: row[0] for row in cursor.fetchall()}
    print(f"Found {len(episode_lookup)} episodes in database")

    topics_loaded = 0
    mappings_created = 0

    for topic_file in topic_files:
        topic = parse_topic_file(topic_file)

        # Insert topic if not exists
        cursor.execute("SELECT topic_id FROM Topics WHERE topic_slug = ?", topic['topic_slug'])
        row = cursor.fetchone()
        if row:
            topic_id = row[0]
        else:
            cursor.execute("""
                INSERT INTO Topics (topic_name, topic_slug)
                VALUES (?, ?)
            """, (topic['topic_name'], topic['topic_slug']))
            topic_id = cursor.execute("SELECT @@IDENTITY").fetchone()[0]
            topics_loaded += 1

        # Map episodes to topic
        for folder_name in topic['episodes']:
            episode_id = episode_lookup.get(folder_name)
            if episode_id:
                try:
                    cursor.execute("""
                        INSERT INTO EpisodeTopics (episode_id, topic_id)
                        VALUES (?, ?)
                    """, (episode_id, topic_id))
                    mappings_created += 1
                except pyodbc.IntegrityError:
                    pass  # Already mapped

    conn.commit()
    cursor.close()
    conn.close()

    print(f"\nComplete: {topics_loaded} topics loaded, {mappings_created} episode-topic mappings created")
    return topics_loaded, mappings_created

if __name__ == "__main__":
    load_topics()
