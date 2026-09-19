# RU and EN frequency dictionary attribution

The files `ru_50k.txt` and `en_50k.txt` are unmodified copies of the 2018
50,000-word frequency lists distributed by **Dave (hermitdave)** in
[FrequencyWords](https://github.com/hermitdave/FrequencyWords), commit
`525f9b560de45753a5ea01069454e72e9aa541c6`.

The repository explicitly licenses **content under Creative Commons
Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**, separately from its
MIT-licensed generator code. See `UPSTREAM-README.md`, the bundled
`CC-BY-SA-4.0.txt`, and <https://creativecommons.org/licenses/by-sa/4.0/>.
The dictionary data is not relicensed under the application's code license.
Retain these credits and license information with redistribution; adaptations
of the dictionary data remain subject to the same ShareAlike terms.

FrequencyWords generated these lists from the **OpenSubtitles2018** corpus
distributed through **OPUS**. Original dataset:
<https://opus.nlpl.eu/OpenSubtitles2018.php>.

## Exact sources and checksums

- Russian: <https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/ru/ru_50k.txt>
  - 998,861 bytes
  - SHA-256: `6095f507cc167488ec66ada5a85ac50433503a08ad24a07c6eabdf54352c4e7f`
- English: <https://github.com/hermitdave/FrequencyWords/blob/525f9b560de45753a5ea01069454e72e9aa541c6/content/2018/en/en_50k.txt>
  - 622,749 bytes
  - SHA-256: `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458`

The predictor filters nonalphabetic words and words outside the selected
language's alphabet in memory. It does not modify the source files. Frequencies
reflect subtitle dialogue, so technical vocabulary and newer words may be
absent, and some suggestions can contain adult language.
