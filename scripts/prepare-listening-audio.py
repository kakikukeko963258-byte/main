"""Prepare the three textbook recordings and word times for offline listening.

Requires ffmpeg/ffprobe, pocketsphinx==5.0.4, g2p-en, num2words and nltk.
Only the three overview recordings linked in the public textbook index are used.
Publisher paragraph times anchor the forced alignment to the actual recordings.
"""
import argparse
import hashlib
import html
import json
import pathlib
import re
import subprocess
import unicodedata
import urllib.request

from g2p_en import G2p
from num2words import num2words
from pocketsphinx import Decoder

BOOK = 'utanbzy9t6'
BASE = f'https://cds.chart.co.jp/assets/contents/books/{BOOK}/'
LESSONS = {1: '141', 2: '171', 3: '201'}


def fetch(url):
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def nodes(node):
    yield node
    for child in node.get('children', []):
        yield from nodes(child)


def normalized(token):
    token = unicodedata.normalize('NFKD', token).replace('’', "'").lower()
    # Parenthetical unit/initialism glosses are printed, but not repeated by
    # the textbook narrator after their spelled-out forms.
    if token.startswith('(') and token.strip('().,;:!?') in {'iss', 'km/h', 'bpm'}:
        return []
    token = token.replace('km/h', 'kilometers per hour').replace('%', ' percent')
    token = re.sub(r'(?<=\d),(?=\d)', '', token)
    token = re.sub(r'\b(19\d{2}|20\d{2})\b', lambda m: num2words(int(m[0]), to='year'), token)
    token = re.sub(r'\d+(?:\.\d+)?', lambda m: num2words(m[0]), token)
    token = re.sub(r'\biss\b', 'i s s', token)
    token = re.sub(r'\bbpm\b', 'b p m', token)
    return re.findall(r"[a-z]+(?:'[a-z]+)?", token)


def canonical(text):
    return re.sub(r'[^a-z0-9]', '', html.unescape(re.sub('<[^>]*>', '', text)).lower())


def pcm(path):
    return subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 's16le', '-ar', '16000', '-ac', '1', '-'])


def align(text, data, g2p):
    decoder = Decoder(samprate=16000, loglevel='ERROR')
    words, owners, spans = [], [], []
    for match in re.finditer(r'\S+', text):
        spans.append((len(text[:match.start()].encode('utf-16-le')) // 2,
                      len(match[0].encode('utf-16-le')) // 2))
        for word in normalized(match[0]):
            if not decoder.lookup_word(word):
                phones = [re.sub(r'\d', '', p) for p in g2p(word) if re.fullmatch(r'[A-Z]+\d?', p)]
                if not phones:
                    raise ValueError(f'No pronunciation for {word}')
                decoder.add_word(word, ' '.join(phones), False)
            words.append(word)
            owners.append(len(spans) - 1)
    decoder.set_align_text(' '.join(words))
    decoder.start_utt()
    decoder.process_raw(data, full_utt=True)
    decoder.end_utt()
    segments = [s for s in decoder.seg() if s.word not in ('<s>', '</s>', '<sil>', '[SPEECH]', '[NOISE]')]
    assert [re.sub(r'\(\d+\)$', '', s.word) for s in segments] == words, 'Alignment sequence differs'
    grouped = {}
    for segment, owner in zip(segments, owners):
        if owner not in grouped:
            grouped[owner] = dict(start=segment.start_frame / 100,
                                  end=(segment.end_frame + 1) / 100,
                                  location=spans[owner][0], length=spans[owner][1])
        else:
            grouped[owner]['end'] = (segment.end_frame + 1) / 100
    return list(grouped.values())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--resources', type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1] / 'Main/Listening/Resources')
    args = parser.parse_args()
    resources = args.resources
    audio_dir = resources / 'Audio'
    book = json.loads(fetch(BASE + 'book.json'))
    index = {str(x.get('id')): x for x in nodes(book)}
    tracks = json.loads((resources / 'tracks.json').read_text(encoding='utf-8-sig'))
    g2p = G2p()
    timelines, sources = {}, []
    for track in tracks:
        photo = track['id']
        entry = index[LESSONS[photo]]
        content = entry['content']
        script = json.loads(fetch(BASE + content['script_file_path']))
        paragraphs = script['children']
        full_text = '\n\n'.join(track['sections'])
        paragraph_spans = list(re.finditer(r'\S(?:.*?\S)?(?=(?:\r?\n){2}|$)', full_text, re.S))
        original_paragraphs = [m[0] for m in paragraph_spans]
        assert len(paragraphs) == len(original_paragraphs), f'Photo {photo}: paragraph count'
        assert all(canonical(a) == canonical(b['text']) for a, b in zip(original_paragraphs, paragraphs)), f'Photo {photo}: text differs'
        full_path = audio_dir / f'photo-{photo}-full.mp3'
        recording = fetch(BASE + content['contents_file_path'])
        full_path.write_bytes(recording)
        raw = pcm(full_path)
        total_seconds = len(raw) / 32000
        full_words = []
        for i, (text, paragraph) in enumerate(zip(original_paragraphs, paragraphs)):
            character_offset = len(full_text[:paragraph_spans[i].start()].encode('utf-16-le')) // 2
            start = paragraph['position'] / 1000
            end = paragraphs[i + 1]['position'] / 1000 if i + 1 < len(paragraphs) else total_seconds
            first_sample, last_sample = round(start * 16000), round(end * 16000)
            print(f'Align photo {photo}, paragraph {i+1}, {start:.2f}-{end:.2f}s', flush=True)
            words = align(text, raw[first_sample * 2:last_sample * 2], g2p)
            full_words.extend(dict(start=round(w['start'] + start, 3), end=round(w['end'] + start, 3),
                                   location=w['location'] + character_offset, length=w['length']) for w in words)
        timelines[f'photo-{photo}-full'] = full_words
        paragraph_index, chapter_char_offset = 0, 0
        chapter_starts = []
        for chapter, section in enumerate(track['sections'], 1):
            start = 0 if chapter == 1 else paragraphs[paragraph_index]['position'] / 1000
            paragraph_index += len(re.split(r'(?:\r?\n){2,}', section))
            end = paragraphs[paragraph_index]['position'] / 1000 if paragraph_index < len(paragraphs) else total_seconds
            path = audio_dir / f'photo-{photo}-chapter-{chapter}.mp3'
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(start), '-i', str(full_path),
                            '-t', str(end - start), '-ar', '24000', '-ac', '1', '-b:a', '96k', str(path)], check=True)
            section_length = len(section.encode('utf-16-le')) // 2
            words = [dict(start=round(max(0, w['start'] - start), 3), end=round(w['end'] - start, 3),
                          location=w['location'] - chapter_char_offset, length=w['length'])
                     for w in full_words if chapter_char_offset <= w['location'] < chapter_char_offset + section_length]
            timelines[path.stem] = words
            chapter_char_offset += section_length + 2
            chapter_starts.append(start)
            print(f'Photo {photo}, chapter {chapter}: {len(words)} word spans; {end-start:.2f}s', flush=True)
        sources.append(dict(photo=photo, lesson=entry.get('content_title'),
                            page=f'https://cds.chart.co.jp/books/{BOOK}/lessons/{entry["id"]}',
                            audio=BASE + content['contents_file_path'],
                            script=BASE + content['script_file_path'],
                            sha256=hashlib.sha256(recording).hexdigest(), chapterStarts=chapter_starts,
                            durationSeconds=total_seconds))
    (resources / 'word-timings.json').write_text(json.dumps(timelines, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (resources / 'audio-sources.json').write_text(json.dumps(sources, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Prepared all 15 textbook recordings and word timelines.', flush=True)


if __name__ == '__main__':
    main()
