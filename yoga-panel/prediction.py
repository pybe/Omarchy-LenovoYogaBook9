"""Offline RU/EN word completion and conservative typo candidates.

Dictionary data has separate CC BY-SA 4.0 terms: see data/ATTRIBUTION.md.
"""

from bisect import bisect_left
import heapq
from pathlib import Path


class Predictor:
    """Load frequency lists lazily and suggest complete words, by frequency."""

    def __init__(self, base_dir=None):
        self.base_dir = Path(base_dir) if base_dir is not None else Path(__file__).resolve().parent / "data"
        self._dictionaries = {}

    def _load(self, language):
        if language not in self._dictionaries:
            frequencies = {}
            with (self.base_dir / f"{language}_50k.txt").open(encoding="utf-8") as source:
                for line in source:
                    fields = line.rsplit(maxsplit=1)
                    if len(fields) != 2:
                        continue
                    word, count_text = fields
                    word = word.lower()
                    if not word.isalpha():
                        continue
                    # Do not mix alphabets or subtitle markup into suggestions.
                    if language == "en" and not all("a" <= c <= "z" for c in word):
                        continue
                    if language == "ru" and not all("а" <= c <= "я" or c == "ё" for c in word):
                        continue
                    try:
                        count = int(count_text)
                    except ValueError:
                        continue
                    if count <= 0:
                        continue
                    frequencies[word] = max(count, frequencies.get(word, 0))
            words = sorted(frequencies)
            self._dictionaries[language] = (words, frequencies)
        return self._dictionaries[language]

    def suggest(self, prefix, language, limit=3):
        if not isinstance(prefix, str) or len(prefix) < 2 or not prefix.isalpha():
            return []
        if language not in ("ru", "en") or not isinstance(limit, int) or limit < 1:
            return []
        normalized = prefix.lower()
        words, frequencies = self._load(language)
        start = bisect_left(words, normalized)
        end = bisect_left(words, normalized + "\U0010ffff")
        # Yield only strict completions. Deterministic alphabetic tie-breaking.
        candidates = (words[i] for i in range(start, end) if words[i] != normalized)
        best = heapq.nsmallest(limit, candidates, key=lambda word: (-frequencies[word], word))
        if prefix.isupper():
            return [word.upper() for word in best]
        if prefix.istitle():
            return [word.title() for word in best]
        # Preserve even mixed casing in the characters the user already entered.
        return [prefix + word[len(prefix):] for word in best]

    def corrections(self, word, language, limit=3, infinitive=False):
        """One insertion, deletion, substitution or adjacent transposition."""
        if language not in ('ru', 'en') or not isinstance(word, str) or not 4 <= len(word) <= 32:
            return []
        alphabet = 'abcdefghijklmnopqrstuvwxyz' if language == 'en' else 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
        lower = word.lower()
        if any(c not in alphabet for c in lower): return []
        _, frequencies = self._load(language)
        if lower in frequencies: return []
        edits = set()
        for i in range(len(lower)+1):
            left, right = lower[:i], lower[i:]
            edits.update(left+c+right for c in alphabet)
            if right:
                edits.add(left+right[1:])
                edits.update(left+c+right[1:] for c in alphabet)
            if len(right)>1: edits.add(left+right[1]+right[0]+right[2:])
        candidates = {w for w in edits if w in frequencies}
        if infinitive:
            candidates = {w for w in candidates if w.endswith(('ть','ться'))}
        if not candidates and len(lower)>=5:
            # Bounded fallback for two mistakes, without generating millions of edits.
            for candidate in frequencies:
                if abs(len(candidate)-len(lower))>2: continue
                if infinitive and not candidate.endswith(('ть','ться')): continue
                if self.distance(lower,candidate)<=2: candidates.add(candidate)
        ranked = sorted(candidates, key=lambda w: (-frequencies[w], w))[:limit]
        return [w.upper() if word.isupper() else w.title() if word.istitle() else w for w in ranked]

    @staticmethod
    def distance(a, b):
        previous = list(range(len(b)+1))
        older = None
        for i, ca in enumerate(a,1):
            row = [3]*(len(b)+1)
            row[0] = i
            for j in range(max(1,i-2),min(len(b),i+2)+1):
                row[j] = min(previous[j]+1,row[j-1]+1,previous[j-1]+(ca!=b[j-1]))
                if older is not None and j>1 and ca==b[j-2] and a[i-2]==b[j-1]:
                    row[j] = min(row[j],older[j-2]+1)
            if min(row)>2: return 3
            older,previous = previous,row
        return previous[-1]

    def correction(self, word, language, previous_word=''):
        infinitive = language=='ru' and previous_word.lower() in ('буду','будешь','будет','будем','будете','будут')
        candidates = self.corrections(word, language, infinitive=infinitive)
        if not candidates or (not word.islower() and not word.istitle()): return None
        _, frequencies = self._load(language)
        top = frequencies[candidates[0].lower()]
        # Unknown names and ambiguous words stay as typed.
        if top < 1000 or (len(candidates)>1 and top < 5*frequencies[candidates[1].lower()]): return None
        return candidates[0]
