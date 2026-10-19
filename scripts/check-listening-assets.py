"""Verify the shipped audio provenance and UTF-16 word ranges without network access."""
import hashlib
import json
import math
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'Main/Listening/Resources'
tracks = json.loads((root / 'tracks.json').read_text(encoding='utf-8-sig'))
timelines = json.loads((root / 'word-timings.json').read_text())
sources = json.loads((root / 'audio-sources.json').read_text())
assert len(sources) == len(tracks) == 3
expected_keys = set()
total_words = 0
for track, source in zip(tracks, sources):
    photo = track['id']
    assert source['photo'] == photo
    full_audio = root / 'Audio' / f'photo-{photo}-full.mp3'
    assert hashlib.sha256(full_audio.read_bytes()).hexdigest() == source['sha256']
    starts = source['chapterStarts']
    assert len(starts) == len(track['sections']) == 4
    assert starts[0] == 0 and all(a < b for a, b in zip(starts, starts[1:]))
    full_key = f'photo-{photo}-full'
    full_words = timelines[full_key]
    full_text = '\n\n'.join(track['sections'])
    char_offset = 0
    for chapter in range(-1, len(track['sections'])):
        key = full_key if chapter < 0 else f'photo-{photo}-chapter-{chapter+1}'
        expected_keys.add(key)
        assert (root / 'Audio' / (key + '.mp3')).stat().st_size > 10000
        text = full_text if chapter < 0 else track['sections'][chapter]
        encoded = text.encode('utf-16-le')
        words = timelines[key]
        assert words, key
        duration = source['durationSeconds'] if chapter < 0 else (starts[chapter+1] if chapter < 3 else source['durationSeconds']) - starts[chapter]
        for word in words:
            assert all(math.isfinite(word[x]) for x in ('start', 'end'))
            assert 0 <= word['start'] < word['end'] <= duration + .12, (key, word)
            start, end = word['location'], word['location'] + word['length']
            assert 0 <= start < end <= len(encoded) // 2, (key, word)
            assert encoded[start*2:end*2].decode('utf-16-le').strip()
        assert all(a['end'] <= b['start'] + .001 and a['location'] < b['location'] for a, b in zip(words, words[1:])), key
        if chapter >= 0:
            part = [w for w in full_words if char_offset <= w['location'] < char_offset + len(encoded)//2]
            assert len(part) == len(words)
            for a, b in zip(part, words):
                assert a['location'] - char_offset == b['location'] and a['length'] == b['length']
                assert abs(a['start'] - starts[chapter] - b['start']) <= .002
                assert abs(a['end'] - starts[chapter] - b['end']) <= .002
            char_offset += len(encoded)//2 + 2
        total_words += len(words)
assert set(timelines) == expected_keys
print(f'Listening assets OK: 15 MP3s, 3 source hashes, {total_words} word spans, chapter/full timing consistency.')
