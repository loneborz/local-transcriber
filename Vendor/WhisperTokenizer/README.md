# Whisper tokenizer (vendored)

The tokenizer of Whisper Large V3 Turbo, bundled so that recognition never
fetches it from the network (LTR-76, doc-3 Addendum 8 D5). WhisperKit reads it
from `Contents/Resources/WhisperTokenizer/`; the model itself is not bundled
(it is downloaded on request in Settings).

| File | Size | SHA-256 |
| --- | --- | --- |
| `config.json` | 1,272 B | `ad0e8d1e46f4d01f7861a21509e5d0f977d6cc1f367a370603c92541d819807b` |
| `tokenizer.json` | 2,480,617 B | `6d8cbd7cd0d8d5815e478dac67b85a26bbe77c1f5e0c6d76d1ce2abc0e5f21ca` |
| `tokenizer_config.json` | 282,843 B | `844b642c73a91359722f47b35705f7174686df33d252695d8572cf9ac03a6389` |

Source: `https://huggingface.co/openai/whisper-large-v3` at commit
`06f233fe06e710322aca913c1bc4249a0d71fce1`, unmodified (fetched once in LTR-66).
Licence: Apache License 2.0 (the repository's `license: apache-2.0`), copyright
OpenAI. The notice is in the app's credits (`LocalTranscriber/Credits.rtf`).

The Xcode "Embed Whisper tokenizer" build phase copies the three files to
`Contents/Resources/WhisperTokenizer/`. Plain data; nothing to sign.
