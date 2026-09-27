# Local Transcriber

A minimal native macOS utility for turning local audio and video into structured transcripts using Apple's on-device SpeechAnalyzer.

## v0.1

Input:
- MP4
- MOV
- M4A
- MP3
- WAV

Pipeline:
- Local audio files are transcribed directly.
- Local video files are normalized/extracted to audio when needed.
- Transcription runs locally using Apple SpeechAnalyzer.

Output:
- transcript.txt
- transcript.json
- transcript.srt
- review.md

## Non-goals

- No cloud transcription
- No accounts
- No URL downloading
- No summarization
- No knowledge base
- No model picker

Drop a file. Get a transcript.
