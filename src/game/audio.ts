export class Sfx {
  private ctx: AudioContext | null = null;

  unlock() {
    const ctx = this.ensure();
    if (ctx.state === "suspended") void ctx.resume();
  }

  jump(double = false) {
    this.tone(double ? 560 : 420, double ? 640 : 220, 0.11, "square", 0.06);
  }

  coin() {
    const ctx = this.ensure();
    this.tone(880, 1320, 0.08, "triangle", 0.07);
    this.tone(1320, 1760, 0.1, "sine", 0.04, ctx.currentTime + 0.05);
  }

  land() {
    this.noise(0.06, 0.04, 280);
  }

  checkpoint() {
    const ctx = this.ensure();
    this.tone(520, 780, 0.14, "triangle", 0.06);
    this.tone(780, 1040, 0.18, "sine", 0.05, ctx.currentTime + 0.08);
  }

  die() {
    this.tone(220, 50, 0.35, "sawtooth", 0.07);
    this.noise(0.25, 0.06, 180);
  }

  win() {
    const ctx = this.ensure();
    [523, 659, 784, 1046].forEach((freq, i) => {
      this.tone(freq, freq * 1.01, 0.2, "triangle", 0.06, ctx.currentTime + i * 0.09);
    });
  }

  private ensure() {
    if (!this.ctx) this.ctx = new AudioContext();
    if (this.ctx.state === "suspended") void this.ctx.resume();
    return this.ctx;
  }

  private tone(
    from: number,
    to: number,
    dur: number,
    type: OscillatorType,
    vol: number,
    when?: number,
  ) {
    const ctx = this.ensure();
    const t = when ?? ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(from, t);
    osc.frequency.exponentialRampToValueAtTime(Math.max(40, to), t + dur);
    gain.gain.setValueAtTime(vol, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + dur);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + dur + 0.02);
  }

  private noise(dur: number, vol: number, cutoff: number) {
    const ctx = this.ensure();
    const n = Math.max(1, Math.floor(ctx.sampleRate * dur));
    const buffer = ctx.createBuffer(1, n, ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < n; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / n);
    const src = ctx.createBufferSource();
    src.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = cutoff;
    const gain = ctx.createGain();
    gain.gain.value = vol;
    src.connect(filter);
    filter.connect(gain);
    gain.connect(ctx.destination);
    src.start();
  }
}
