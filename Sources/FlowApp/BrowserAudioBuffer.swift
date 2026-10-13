import Foundation

/// A bounded, in-memory audio FIFO. ChatGPT receives the opening audio after its
/// recorder acknowledges startup. No audio is played through the speakers.
enum BrowserAudioBuffer {
    static let queue = #"""
    class FlowAudioQueue {
      constructor(capacity) { this.data = new Float32Array(capacity); this.read = 0; this.write = 0; this.count = 0; this.playing = false; this.stopped = false; this.failed = false; this.level = 0; }
      enqueue(input) {
        if (this.stopped || this.failed) return;
        if (this.count + input.length > this.data.length) { this.failed = true; this.stopped = true; return; }
        for (const v of input) { this.data[this.write] = v; this.write = (this.write + 1) % this.data.length; }
        this.count += input.length;
      }
      process(input, output) {
        output.fill(0);
        let energy = 0;
        if (!this.stopped && input.length) {
          if (this.count + input.length > this.data.length) { this.failed = true; this.stopped = true; return; }
          for (const v of input) { this.data[this.write] = v; this.write = (this.write + 1) % this.data.length; energy += v * v; }
          this.count += input.length;
        }
        this.level = input.length && !this.stopped ? Math.min(1, Math.sqrt(energy / input.length) * 6) : 0;
        if (this.playing && !this.failed) {
          const n = Math.min(output.length, this.count);
          for (let i = 0; i < n; i++) { output[i] = this.data[this.read]; this.read = (this.read + 1) % this.data.length; }
          this.count -= n;
        }
      }
    }
    """#

    static let script = #"""
    (() => {
      if (location.origin !== 'https://chatgpt.com' || window.__flowAudio) return;
    """# + queue + #"""
      const media = navigator.mediaDevices;
      if (!media) return;
      const original = media.getUserMedia.bind(media);
      let current = null;
      const teardown = async () => {
        const c = current; current = null;
        if (!c) return;
        c.stream?.getTracks().forEach(t => t.stop());
        c.destination.stream.getTracks().forEach(t => t.stop());
        c.source?.disconnect(); c.node.disconnect();
        if (c.node.onaudioprocess) c.node.onaudioprocess = null;
        await c.context.close();
      };
      const command = mode => {
        const c = current; if (!c) return;
        if (c.node.port) c.node.port.postMessage(mode);
        else if (mode === 'play') c.queue.playing = true;
        else if (mode === 'stop') c.queue.stopped = true;
      };
      window.__flowAudio = {
        async begin(native = false) {
          if (current) throw Error('FlowGpt audio is already active.');
          const devices = native ? [] : await media.enumerateDevices();
          const builtin = devices.find(d => d.kind === 'audioinput' && /macbook|built.?in|internal microphone/i.test(d.label));
          // If labels are unavailable, a normal browser permission is still required.
          // Once available, prefer the Mac microphone to avoid Bluetooth HFP routing.
          const stream = native ? null : await original({audio: {channelCount: 1, echoCancellation: false, noiseSuppression: false, autoGainControl: false, ...(builtin ? {deviceId: {exact: builtin.deviceId}} : {})}, video: false});
          let context;
          try {
            context = new AudioContext(native ? {sampleRate:16000} : {});
            await context.resume();
            if (context.state !== 'running') throw Error('The audio renderer is paused. Open the connection window once, then retry.');
            const source = stream ? context.createMediaStreamSource(stream) : null, destination = context.createMediaStreamDestination();
            if (native && context.sampleRate !== 16000) throw Error('The browser audio renderer did not accept 16 kHz audio.');
            const c = {stream, context, source, destination, node: null, queue: null, level: 0, count: 0, failed: false, attached: false, stopped: false, input: stream?.getAudioTracks()[0]?.label || 'Native microphone'};
            const worklet = String.raw`
    """# + queue + #"""
              class FlowBufferProcessor extends AudioWorkletProcessor {
                constructor() { super(); this.queue = new FlowAudioQueue(Math.ceil(sampleRate * 30)); this.frames = 0; this.port.onmessage = e => { if (e.data === 'play') this.queue.playing = true; else if (e.data === 'stop') this.queue.stopped = true; else if (e.data instanceof Float32Array) this.queue.enqueue(e.data); }; }
                process(inputs, outputs) {
                  const output = outputs[0]?.[0]; if (!output) return true;
                  this.queue.process(inputs[0]?.[0] || new Float32Array(0), output);
                  this.frames += output.length;
                  if (this.frames >= sampleRate / 20) { this.frames = 0; this.port.postMessage({level: this.queue.level, count: this.queue.count, failed: this.queue.failed}); }
                  return true;
                }
              }
              registerProcessor('flow-buffer', FlowBufferProcessor);
            `;
            try {
              if (!context.audioWorklet) throw Error('AudioWorklet unavailable');
              const url = URL.createObjectURL(new Blob([worklet], {type: 'application/javascript'}));
              try { await context.audioWorklet.addModule(url); } finally { URL.revokeObjectURL(url); }
              c.node = new AudioWorkletNode(context, 'flow-buffer', {numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1], channelCount: 1});
              c.node.port.onmessage = e => { c.level = e.data.level; c.count = e.data.count; c.failed = e.data.failed; };
            } catch {
              // ChatGPT CSP/older WebKit may block a blob worklet. Keep the same
              // FIFO with the compatible processor, never silently drop the prefix.
              c.queue = new FlowAudioQueue(Math.ceil(context.sampleRate * 30));
              c.node = context.createScriptProcessor(1024, 1, 1);
              const empty = new Float32Array(0);
              c.node.onaudioprocess = e => { c.queue.process(native ? empty : e.inputBuffer.getChannelData(0), e.outputBuffer.getChannelData(0)); c.level = c.queue.level; c.count = c.queue.count; c.failed = c.queue.failed; };
            }
            source?.connect(c.node); c.node.connect(destination);
            current = c;
            return {input: c.input};
          } catch (error) { stream?.getTracks().forEach(t => t.stop()); if (context) await context.close(); throw error; }
        },
        push(encoded) {
          const c = current; if (!c || c.stopped) throw Error('The native audio destination is unavailable.');
          const binary = atob(encoded), bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
          const samples = new Float32Array(bytes.buffer);
          if (c.node.port) c.node.port.postMessage(samples, [samples.buffer]);
          else { c.queue.enqueue(samples); c.count = c.queue.count; c.failed = c.queue.failed; }
          return true;
        },
        play() { command('play'); },
        stop() { if (current) { current.stopped = true; command('stop'); current.stream?.getTracks().forEach(t => t.stop()); } },
        state() { const c = current; return c ? {active: true, level: c.level, queued: c.count / c.context.sampleRate, failed: c.failed, attached: c.attached, input: c.input} : {active: false, level: 0, queued: 0}; },
        end: teardown
      };
      media.getUserMedia = async constraints => {
        if (current && constraints?.audio && !constraints?.video) { current.attached = true; return current.destination.stream; }
        return original(constraints);
      };
      window.addEventListener('pagehide', () => { void teardown(); });
    })();
    """#
}
