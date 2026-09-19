"""Ordered keyboard edits; stores only the current word and one undo in RAM."""
import time

class Autocorrect:
    def __init__(self, predictor):
        self.predictor = predictor
        self.reset()

    def reset(self):
        self.word = ''
        self.previous_word = ''
        self.undo = None
        self.last = 0
        self.blocked = False

    @staticmethod
    def text(value):
        return [f't {ord(c)} 0' for c in value]

    def process(self, event):
        now = time.monotonic()
        if now-self.last>8: self.reset()
        self.last = now
        kind = event['type']
        if event.get('mods'):
            self.reset()
            return None
        if kind == 'key':
            if event['key'] == 'BackSpace':
                if self.undo:
                    original, replacement = self.undo
                    self.undo = None
                    self.word = original
                    self.blocked = True  # Space after undo must not reapply the correction.
                    return ['k BackSpace 0']*(len(replacement)+1)+self.text(original)
                self.word = self.word[:-1]
            else: self.reset()
            return None
        self.undo = None
        char = event['text']
        if char == ' ' and event.get('autocorrect') and self.word and not self.blocked:
            original = self.word
            try: replacement = self.predictor.correction(original, event.get('language'),self.previous_word)
            except OSError: replacement = None
            self.word = ''
            self.previous_word = replacement or original
            if replacement:
                self.undo = (original, replacement)
                return ['k BackSpace 0']*len(original)+self.text(replacement+' ')
        if char.isalpha():
            if len(self.word)>=64:
                self.word = ''
                self.blocked = True
            self.word += char
        else:
            if self.word: self.previous_word = self.word if char==' ' else ''
            elif char!=' ': self.previous_word = ''
            self.word = ''
            self.blocked = False
        return None
