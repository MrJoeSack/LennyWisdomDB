"""
Load Lenny's Podcast episodes into LennyWisdomDB.
Parses YAML frontmatter, extracts metadata, and loads into Episodes table.
"""

import os
import yaml
import pyodbc
from pathlib import Path

EPISODES_DIR = r"D:\Dropbox\Github\lennys-podcast-transcripts\episodes"
CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"

def parse_episode(folder_path: Path) -> dict:
    """Parse a single episode transcript and extract metadata."""
    transcript_path = folder_path / "transcript.md"
    if not transcript_path.exists():
        return None

    with open(transcript_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract YAML frontmatter
    if not content.startswith('---'):
        return None

    end_idx = content.find('---', 3)
    if end_idx == -1:
        return None

    yaml_content = content[3:end_idx]
    transcript_text = content[end_idx+3:].strip()

    try:
        metadata = yaml.safe_load(yaml_content)
    except yaml.YAMLError as e:
        print(f"YAML error in {folder_path.name}: {e}")
        return None

    return {
        'folder_name': folder_path.name,
        'guest_name': metadata.get('guest', 'Unknown'),
        'episode_title': metadata.get('title', 'Untitled'),
        'youtube_url': metadata.get('youtube_url'),
        'video_id': metadata.get('video_id'),
        'publish_date': metadata.get('publish_date'),
        'duration_seconds': metadata.get('duration_seconds'),
        'duration_display': metadata.get('duration'),
        'view_count': metadata.get('view_count'),
        'description': metadata.get('description', '').strip() if metadata.get('description') else None,
        'keywords': metadata.get('keywords', []),
        'full_transcript': transcript_text
    }

def load_episodes():
    """Load all episodes into the database."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    # Get list of episode folders
    episodes_path = Path(EPISODES_DIR)
    folders = sorted([f for f in episodes_path.iterdir() if f.is_dir()])

    print(f"Found {len(folders)} episode folders")

    loaded = 0
    skipped = 0

    for folder in folders:
        episode = parse_episode(folder)
        if not episode:
            print(f"  Skipping {folder.name} - could not parse")
            skipped += 1
            continue

        # Check if already exists
        cursor.execute("SELECT episode_id FROM Episodes WHERE folder_name = ?", episode['folder_name'])
        if cursor.fetchone():
            skipped += 1
            continue

        # Insert episode
        cursor.execute("""
            INSERT INTO Episodes (
                guest_name, episode_title, youtube_url, video_id, publish_date,
                duration_seconds, duration_display, view_count, description,
                folder_name, full_transcript
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            episode['guest_name'],
            episode['episode_title'],
            episode['youtube_url'],
            episode['video_id'],
            episode['publish_date'],
            episode['duration_seconds'],
            episode['duration_display'],
            episode['view_count'],
            episode['description'],
            episode['folder_name'],
            episode['full_transcript']
        ))

        episode_id = cursor.execute("SELECT @@IDENTITY").fetchone()[0]

        # Insert keywords
        for keyword in episode['keywords']:
            if keyword:
                try:
                    cursor.execute("""
                        INSERT INTO EpisodeKeywords (episode_id, keyword)
                        VALUES (?, ?)
                    """, (episode_id, keyword[:100]))
                except pyodbc.IntegrityError:
                    pass  # Duplicate keyword

        loaded += 1
        if loaded % 50 == 0:
            conn.commit()
            print(f"  Loaded {loaded} episodes...")

    conn.commit()
    cursor.close()
    conn.close()

    print(f"\nComplete: {loaded} loaded, {skipped} skipped")
    return loaded

if __name__ == "__main__":
    load_episodes()
