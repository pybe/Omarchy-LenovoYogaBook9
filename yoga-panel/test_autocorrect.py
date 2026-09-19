import unittest
from autocorrect import Autocorrect
from prediction import Predictor

class CorrectionTests(unittest.TestCase):
    def setUp(self):
        self.predictor=Predictor()
        self.engine=Autocorrect(self.predictor)
        self.value=''
    def event(self,e):
        commands=self.engine.process(e)
        if commands is None:
            commands=['k BackSpace 0'] if e['type']=='key' else self.engine.text(e['text'])
        for command in commands:
            if command.startswith('k BackSpace'): self.value=self.value[:-1]
            elif command.startswith('t '): self.value+=chr(int(command.split()[1]))
    def type(self,text,enabled=True,language='ru'):
        for c in text: self.event(dict(type='text',text=c,autocorrect=enabled,language=language))
    def test_typo_and_undo(self):
        self.type('првиет ');self.assertEqual(self.value,'привет ')
        self.event(dict(type='key',key='BackSpace'))
        self.assertEqual(self.value,'првиет')
        self.type(' ');self.assertEqual(self.value,'првиет ')
    def test_future_context_two_errors(self):
        self.type('буду провирят ')
        self.assertEqual(self.value,'буду проверять ')
        self.event(dict(type='key',key='BackSpace'))
        self.assertEqual(self.value,'буду провирят')
    def test_en(self):
        self.type('Helllo ',language='en');self.assertEqual(self.value,'Hello ')
    def test_disabled_known_and_unknown(self):
        self.type('првиет ',False);self.type('привет ксдфгт ')
        self.assertEqual(self.value,'првиет привет ксдфгт ')
    def test_new_text_invalidates_undo(self):
        self.type('првиет а');self.event(dict(type='key',key='BackSpace'))
        self.assertEqual(self.value,'привет ')
    def test_context_reset_and_timeout(self):
        self.type('првиет');self.engine.reset();self.type(' ')
        self.assertEqual(self.value,'првиет ')
        self.type('првиет');self.engine.last=0;self.type(' ')
        self.assertEqual(self.value,'првиет првиет ')
    def test_candidates(self):
        for word in ['првиет','приветт','привт']:
            self.assertIn('привет',self.predictor.corrections(word,'ru'))
        self.assertIsNone(self.predictor.correction('привет','ru'))
        self.assertIsNone(self.predictor.correction('XYZ123','en'))
if __name__=='__main__': unittest.main()
