"""
Parse Lenny's Podcast transcripts into Q&A pairs (semantic chunks).

- Groups Lenny's questions with guest answers
- Strips sponsor/ad segments
- Splits long answers with overlap, prepending question as context
"""

import re
import pyodbc
from typing import List

CONN_STR = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=LennyWisdomDB;Trusted_Connection=yes;"

# Episode range to process
EPISODE_MIN = 1
EPISODE_MAX = 999

# Chunk size limits (in characters)
MAX_CHUNK_SIZE = 2500  # ~625 tokens
OVERLAP_PCT = 0.15     # 15% overlap for split chunks

# Sponsor detection patterns
SPONSOR_PATTERNS = [
    r"This episode is brought to you by",
    r"brought to you by",
    r"Today's episode is sponsored",
    r"This podcast is brought to you",
    r"special offer just for",
    r"Use code .* for .* off",
    r"visit .+\.com/lenny",
    r"head over to .+\.com",
    r"check out .+\.com",
    r"That's .+-.*\.com",
    r"Sign up.*free trial",
    r"limited time offer",
    r"\.com/lenny",
    r"promo code",
    r"discount code",
]

def is_sponsor_segment(text: str) -> bool:
    """Detect if a text segment is likely a sponsor read."""
    text_lower = text.lower()

    # Check for sponsor patterns
    for pattern in SPONSOR_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE):
            # Additional check: must be substantial ad content
            # Short mentions of sponsors in conversation are OK
            sponsor_keywords = ['discount', 'promo', 'offer', 'free trial', 'sign up',
                              'check out', 'head over', 'use code', 'credit']
            keyword_count = sum(1 for kw in sponsor_keywords if kw in text_lower)
            if keyword_count >= 2 or len(text) > 500:
                return True
    return False

def parse_timestamp(ts_str: str) -> int:
    """Convert HH:MM:SS or MM:SS to seconds."""
    parts = ts_str.split(':')
    if len(parts) == 3:
        return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    elif len(parts) == 2:
        return int(parts[0]) * 60 + int(parts[1])
    return 0

def parse_speaker_turns(transcript: str, guest_name: str) -> List[dict]:
    """Parse transcript into speaker turns with timestamps."""
    # Multiple formats to handle:
    # Format 1: "Speaker Name (HH:MM:SS):" - parentheses with HH:MM:SS
    # Format 2: "Speaker Name (MM:SS):" - parentheses with MM:SS
    # Format 3: "[HH:MM:SS] Speaker:" - brackets before speaker
    # Format 4: "Speaker Name:" - no timestamp

    lines = transcript.split('\n')
    turns = []
    current_speaker = None
    current_timestamp = None
    current_text_lines = []
    turn_index = 0

    # Detect format
    has_paren_hhmmss = bool(re.search(r'\(\d{1,2}:\d{2}:\d{2}\):', transcript))
    has_paren_mmss = bool(re.search(r'\(\d{1,2}:\d{2}\):', transcript))
    has_bracket = bool(re.search(r'\[\d{1,2}:\d{2}:\d{2}\]', transcript))

    for line in lines:
        stripped = line.strip()
        match = None
        speaker = None
        timestamp = None

        if has_paren_hhmmss:
            # Format 1: "Speaker Name (HH:MM:SS):" - use \w and Unicode
            m = re.match(r'^([\w][\w\s\.\-\']+?)?\s*\((\d{1,2}:\d{2}:\d{2})\):\s*$', stripped, re.UNICODE)
            if m:
                match = m
                speaker = m.group(1)
                timestamp = m.group(2)
        elif has_paren_mmss:
            # Format 2: "Speaker Name (MM:SS):"
            m = re.match(r'^([\w][\w\s\.\-\']+?)\s*\((\d{1,2}:\d{2})\):\s*$', stripped, re.UNICODE)
            if m:
                match = m
                speaker = m.group(1)
                timestamp = m.group(2)
        elif has_bracket:
            # Format 3: "[HH:MM:SS] Speaker:" - speaker and timestamp on same line, content follows
            m = re.match(r'^\[(\d{1,2}:\d{2}:\d{2})\]\s*([\w][\w\s\.\-\']*?):\s*(.*)$', stripped, re.UNICODE)
            if m:
                match = m
                timestamp = m.group(1)
                speaker = m.group(2)
                # Content is on same line
                content = m.group(3).strip()

                # Save previous turn
                if current_speaker and current_text_lines:
                    text = ' '.join(current_text_lines).strip()
                    text = re.sub(r'\s+', ' ', text)
                    if text:
                        turns.append({
                            'speaker': current_speaker,
                            'timestamp': current_timestamp or '00:00:00',
                            'timestamp_seconds': parse_timestamp(current_timestamp) if current_timestamp else turn_index * 60,
                            'text': text
                        })
                        turn_index += 1
                    current_text_lines = []

                if speaker:
                    current_speaker = speaker.strip()
                current_timestamp = timestamp
                if content:
                    current_text_lines.append(content)
                continue
        else:
            # Format 4: "Speaker Name:" alone on line
            m = re.match(r'^([\w][\w\s\.\-\']+?):\s*$', stripped, re.UNICODE)
            if m:
                match = m
                speaker = m.group(1)

        if match and not has_bracket:
            # Save previous turn
            if current_speaker and current_text_lines:
                text = ' '.join(current_text_lines).strip()
                text = re.sub(r'\s+', ' ', text)
                if text:
                    turns.append({
                        'speaker': current_speaker,
                        'timestamp': current_timestamp or '00:00:00',
                        'timestamp_seconds': parse_timestamp(current_timestamp) if current_timestamp else turn_index * 60,
                        'text': text
                    })
                    turn_index += 1
                current_text_lines = []

            if speaker:
                current_speaker = speaker.strip()
            current_timestamp = timestamp
        elif not has_bracket:
            # Content line
            if stripped:
                current_text_lines.append(stripped)

    # Save last turn
    if current_speaker and current_text_lines:
        text = ' '.join(current_text_lines).strip()
        text = re.sub(r'\s+', ' ', text)
        if text:
            turns.append({
                'speaker': current_speaker,
                'timestamp': current_timestamp or '00:00:00',
                'timestamp_seconds': parse_timestamp(current_timestamp) if current_timestamp else turn_index * 60,
                'text': text
            })

    return turns

def is_lenny(speaker: str) -> bool:
    """Check if speaker is Lenny."""
    return speaker and 'lenny' in speaker.lower()

def group_qa_pairs(turns: List[dict], guest_name: str) -> List[dict]:
    """Group turns into Q&A pairs (Lenny question + guest answer)."""
    qa_pairs = []
    i = 0

    while i < len(turns):
        turn = turns[i]

        # Skip sponsor segments
        if is_sponsor_segment(turn['text']):
            i += 1
            continue

        # Collect consecutive Lenny turns as question
        question_parts = []
        question_start = turn['timestamp']
        question_start_sec = turn['timestamp_seconds']

        while i < len(turns) and is_lenny(turns[i]['speaker']):
            if not is_sponsor_segment(turns[i]['text']):
                question_parts.append(turns[i]['text'])
            i += 1

        if not question_parts:
            i += 1
            continue

        question_text = '\n\n'.join(question_parts)

        # Collect consecutive guest turns as answer
        answer_parts = []
        answer_speaker = None
        answer_end = question_start
        answer_end_sec = question_start_sec

        while i < len(turns) and not is_lenny(turns[i]['speaker']):
            if not is_sponsor_segment(turns[i]['text']):
                answer_parts.append(turns[i]['text'])
                answer_speaker = turns[i]['speaker']
                answer_end = turns[i]['timestamp']
                answer_end_sec = turns[i]['timestamp_seconds']
            i += 1

        if answer_parts:
            answer_text = '\n\n'.join(answer_parts)
            qa_pairs.append({
                'question': question_text,
                'answer': answer_text,
                'question_speaker': 'Lenny',
                'answer_speaker': answer_speaker or guest_name,
                'start_timestamp': question_start,
                'end_timestamp': answer_end,
                'start_seconds': question_start_sec,
                'end_seconds': answer_end_sec
            })

    return qa_pairs

def split_long_chunk(qa_pair: dict, max_size: int, overlap_pct: float) -> List[dict]:
    """Split a long Q&A pair into multiple chunks with overlap."""
    combined = f"Q: {qa_pair['question']}\n\nA: {qa_pair['answer']}"

    if len(combined) <= max_size:
        return [{
            **qa_pair,
            'chunk_text': combined,
            'is_split': False,
            'split_part': 1
        }]

    # Need to split - keep question as context header for each chunk
    # If question is too long, truncate it for the header
    question = qa_pair['question']
    if len(question) > max_size // 2:
        question = question[:max_size // 2 - 50] + "..."

    question_header = f"Q: {question}\n\nA: "
    header_len = len(question_header)
    answer = qa_pair['answer']

    # Available space for answer text per chunk - ensure at least 500 chars
    available = max(500, max_size - header_len)
    overlap = int(available * overlap_pct)

    # Ensure we always advance by at least 100 chars
    min_step = max(100, available - overlap)

    chunks = []
    pos = 0
    part = 1

    while pos < len(answer):
        end = min(pos + available, len(answer))

        # Try to break at sentence boundary
        if end < len(answer):
            # Look for sentence end in last 20% of chunk
            search_start = pos + int(available * 0.8)
            if search_start < end:
                search_text = answer[search_start:end]
                sentence_end = max(
                    search_text.rfind('. '),
                    search_text.rfind('? '),
                    search_text.rfind('! ')
                )
                if sentence_end > 0:
                    end = search_start + sentence_end + 2

        chunk_answer = answer[pos:end].strip()
        chunk_text = question_header + chunk_answer

        chunks.append({
            **qa_pair,
            'chunk_text': chunk_text,
            'is_split': True,
            'split_part': part
        })

        # Always advance by at least min_step to prevent infinite loop
        if end >= len(answer):
            break
        new_pos = end - overlap
        if new_pos <= pos:
            new_pos = pos + min_step
        pos = new_pos
        part += 1

        # Safety: limit to 100 chunks per Q&A pair
        if part > 100:
            break

    return chunks

def process_episode(episode_id: int, guest_name: str, transcript: str) -> List[dict]:
    """Process a single episode transcript into chunks."""
    turns = parse_speaker_turns(transcript, guest_name)
    if not turns:
        return []

    qa_pairs = group_qa_pairs(turns, guest_name)

    # Split long chunks
    all_chunks = []
    for qa in qa_pairs:
        chunks = split_long_chunk(qa, MAX_CHUNK_SIZE, OVERLAP_PCT)
        all_chunks.extend(chunks)

    return all_chunks

def load_chunks():
    """Process episodes 1-75 and load chunks into database."""
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()

    # Get episodes in batch range, excluding already processed
    cursor.execute("""
        SELECT e.episode_id, e.guest_name, e.full_transcript
        FROM Episodes e
        WHERE e.episode_id BETWEEN ? AND ?
          AND e.full_transcript IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM EpisodeChunks ec WHERE ec.episode_id = e.episode_id)
        ORDER BY e.episode_id
    """, (EPISODE_MIN, EPISODE_MAX))
    episodes = cursor.fetchall()

    print("=" * 60)
    print(f"Lenny's Podcast Q&A Chunker - Episodes {EPISODE_MIN}-{EPISODE_MAX}")
    print("=" * 60)
    print(f"Episodes to process: {len(episodes)}")
    print("-" * 60)

    total_chunks = 0
    processed_count = 0

    for episode_id, guest_name, transcript in episodes:
        chunks = process_episode(episode_id, guest_name, transcript)

        for seq, chunk in enumerate(chunks, 1):
            cursor.execute("""
                INSERT INTO EpisodeChunks (
                    episode_id, chunk_sequence, speaker_question, speaker_answer,
                    chunk_text, question_speaker, answer_speaker,
                    start_timestamp, end_timestamp, start_seconds,
                    char_count, is_split, split_part
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                episode_id,
                seq,
                chunk['question'],
                chunk['answer'],
                chunk['chunk_text'],
                chunk['question_speaker'],
                chunk['answer_speaker'],
                chunk['start_timestamp'],
                chunk['end_timestamp'],
                chunk['start_seconds'],
                len(chunk['chunk_text']),
                1 if chunk['is_split'] else 0,
                chunk['split_part']
            ))

        total_chunks += len(chunks)
        processed_count += 1

        print(f"Episode {episode_id} ({guest_name}): {len(chunks)} chunks")

        # Commit every 10 episodes
        if processed_count % 10 == 0:
            conn.commit()
            print(f"  [Committed {processed_count} episodes, {total_chunks} chunks]")

    conn.commit()

    # Get stats for batch
    cursor.execute("""
        SELECT COUNT(*), AVG(char_count), MAX(char_count)
        FROM EpisodeChunks
        WHERE episode_id BETWEEN ? AND ?
    """, (EPISODE_MIN, EPISODE_MAX))
    count, avg_size, max_size = cursor.fetchone()

    cursor.execute("""
        SELECT COUNT(*)
        FROM EpisodeChunks
        WHERE episode_id BETWEEN ? AND ?
          AND is_split = 1
    """, (EPISODE_MIN, EPISODE_MAX))
    split_count = cursor.fetchone()[0]

    cursor.close()
    conn.close()

    print("-" * 60)
    print(f"COMPLETE: {processed_count} episodes processed")
    print(f"  Total chunks created: {count}")
    print(f"  Avg chunk size: {int(avg_size) if avg_size else 0} chars")
    print(f"  Max chunk size: {max_size or 0} chars")
    print(f"  Split chunks: {split_count}")
    print("=" * 60)

    return count

if __name__ == "__main__":
    load_chunks()
