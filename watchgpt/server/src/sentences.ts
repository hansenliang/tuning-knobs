// Splits a streaming LLM reply into speakable chunks so TTS can start after
// the first sentence instead of waiting for the whole answer.
// The first chunk is allowed to be short (latency); later ones are longer
// (fewer TTS calls, more natural prosody).

export class SentenceChunker {
  private buf = '';
  private emitted = 0;

  push(delta: string): string[] {
    this.buf += delta;
    const out: string[] = [];
    for (;;) {
      const min = this.emitted === 0 ? 12 : 40;
      const cut = this.findCut(min);
      if (cut < 0) break;
      const chunk = this.buf.slice(0, cut).trim();
      this.buf = this.buf.slice(cut);
      if (chunk) {
        out.push(chunk);
        this.emitted++;
      }
    }
    return out;
  }

  flush(): string[] {
    const rest = this.buf.trim();
    this.buf = '';
    return rest ? [rest] : [];
  }

  private findCut(min: number): number {
    // Sentence end: . ! ? followed by whitespace (avoid "3.5", "e.g.").
    const re = /[.!?]["')\]]?\s+/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(this.buf))) {
      const end = m.index + m[0].length;
      const before = this.buf.slice(Math.max(0, m.index - 3), m.index + 1).toLowerCase();
      if (/\b(e\.g|i\.e|dr|mr|ms|st|vs)\.$/.test(before)) continue;
      if (end >= min) return end;
    }
    // Very long run-on: cut at a clause boundary so speech doesn't stall.
    if (this.buf.length > 160) {
      const clause = Math.max(this.buf.lastIndexOf(', ', 160), this.buf.lastIndexOf('; ', 160), this.buf.lastIndexOf(': ', 160));
      if (clause > min) return clause + 2;
    }
    return -1;
  }
}
