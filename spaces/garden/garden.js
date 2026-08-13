(() => {
  "use strict";

  const field = document.getElementById("garden-field");
  const title = document.getElementById("garden-title");
  const home = document.getElementById("garden-home");
  const toggle = document.getElementById("garden-toggle");
  const status = document.getElementById("garden-status");
  const context = field.getContext("2d");
  const dark = matchMedia("(prefers-color-scheme: dark)");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const radiants = [];
  const waves = [];
  const midiByPitch = {
    C: 0,
    "C#": 1,
    D: 2,
    "D#": 3,
    E: 4,
    F: 5,
    "F#": 6,
    G: 7,
    "G#": 8,
    A: 9,
    "A#": 10,
    B: 11,
  };
  const samples = {
    A0: "samples/8ffa210477305cd91be59e6426ae307a.mp3",
    "C#1": "samples/9a99383df3e0c28bcfde86b53168e0f7.mp3",
    F1: "samples/6dc4d5018a1e5f3f97fb86a89a7a0b28.mp3",
    "C#2": "samples/dbdabadd6c7c340e7637c66c507f9ef7.mp3",
    F2: "samples/4bf8ba32c60b2775615cc7f480dc1a29.mp3",
    A2: "samples/d83cc32322b16071034c0d1812813e0d.mp3",
    "C#3": "samples/666ba1c87cad53070bdba0de69108880.mp3",
    F3: "samples/0d18b615470f87df679f031ffd4af6fd.mp3",
    A3: "samples/466194c6fa91444272fa4f2d2aa2cea9.mp3",
    "C#4": "samples/736a869d72da86b52a79608e7fa3970e.mp3",
    F4: "samples/4d07241597b5ae0292ff52e28beb6843.mp3",
    A4: "samples/74168e979cc6deeb4996f12ade3abaac.mp3",
    "C#5": "samples/130e0aff8b681c3a592e40647a9350cc.mp3",
    F5: "samples/ad56204accd49589d085d08c60f2b460.mp3",
    A5: "samples/d841b0a9f78784d955a4abf6928db31f.mp3",
    "C#6": "samples/de5b50ed89fd51c904f415cca148e8d2.mp3",
    F6: "samples/5ddffd28c17bb4af6a4e79b0eee2bc63.mp3",
    A6: "samples/6646f96a72488c3d7070a71b63d3fd29.mp3",
    "C#7": "samples/6adcfc9db67275b965329113a6cf34a7.mp3",
    F7: "samples/0990e33f4c682d56eb5f1c90fae10e88.mp3",
    A7: "samples/7401f6c7a73186a8928d529a40330f6b.mp3",
    C8: "samples/54eae9a3e66e19449d29676b9da1051e.mp3",
  };

  let columns = 0;
  let rows = 0;
  let cellWidth = 0;
  let cellHeight = 0;
  let sequence = 0;
  let stage;
  let playing = false;

  const noteToMidi = note => {
    const match = /^([A-G]#?)(-?\d+)$/.exec(note);
    return match ? (Number(match[2]) + 1) * 12 + midiByPitch[match[1]] : 60;
  };

  const hueForMidi = midi => (midi * 47) % 360;

  const resize = () => {
    const ratio = devicePixelRatio || 1;
    const width = innerWidth;
    const height = innerHeight;
    const size = Math.max(
      5,
      Math.min(14, width / (54 * .62), height / (54 * 1.2))
    );

    field.width = Math.round(width * ratio);
    field.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.font = `${size}px ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace`;
    context.textBaseline = "top";
    cellWidth = context.measureText(".").width;
    cellHeight = size * 1.2;
    columns = Math.ceil(width / cellWidth);
    rows = Math.ceil(height / cellHeight);

    radiants.length = 0;
    const inset = 4;
    const xStep = (columns - inset * 2 - 1) / 5;
    const yStep = (rows - inset * 2 - 1) / 5;
    for (let y = 0; y < 6; y++) {
      for (let x = 0; x < 6; x++) {
        radiants.push({
          x: Math.round(inset + x * xStep),
          y: Math.round(inset + y * yStep),
        });
      }
    }
    waves.forEach(wave => Object.assign(wave, radiants[wave.slot]));
  };

  const showTitle = () => {
    const hue = Math.floor(Math.random() * 360);
    title.style.color = `hsl(${hue} 82% ${dark.matches ? 70 : 38}%)`;
    title.hidden = false;
    title.classList.remove("blooming");
    void title.offsetWidth;
    title.classList.add("blooming");
  };

  const strike = note => {
    const midi = noteToMidi(note);
    const slot = sequence * 13 % radiants.length;
    waves.push({
      ...radiants[slot],
      born: performance.now(),
      hue: hueForMidi(midi),
      slot,
    });
    sequence++;
  };

  const draw = now => {
    const background = dark.matches ? "#080808" : "#fff";
    const dot = dark.matches ? "#292929" : "#ddd";
    context.fillStyle = background;
    context.fillRect(0, 0, innerWidth, innerHeight);
    context.fillStyle = dot;
    const dottedRow = ".".repeat(columns);
    for (let y = 0; y < rows; y++) {
      context.fillText(dottedRow, 0, y * cellHeight);
    }

    const cells = new Map();
    const speed = reducedMotion.matches ? 2.5 : 5;
    const coolingTime = reducedMotion.matches ? 1800 : 4200;
    const aspect = cellWidth / cellHeight;
    const xGap = (columns - 9) / 5 * aspect;
    const yGap = (rows - 9) / 5;
    const maxRadius = Math.min(xGap, yGap) * 2.65;
    const life = maxRadius / speed * 1000 + coolingTime * 1.5;

    for (let i = waves.length - 1; i >= 0; i--) {
      const wave = waves[i];
      const age = now - wave.born;
      if (age > life) {
        waves.splice(i, 1);
        continue;
      }

      const radius = Math.min(age / 1000 * speed, maxRadius);
      const reach = radius + .5;
      const minX = Math.max(0, Math.floor(wave.x - reach / aspect));
      const maxX = Math.min(columns - 1, Math.ceil(wave.x + reach / aspect));
      const minY = Math.max(0, Math.floor(wave.y - reach));
      const maxY = Math.min(rows - 1, Math.ceil(wave.y + reach));

      for (let y = minY; y <= maxY; y++) {
        for (let x = minX; x <= maxX; x++) {
          const distance = Math.hypot((x - wave.x) * aspect, y - wave.y);
          const arrived = distance / speed * 1000;
          if (distance > maxRadius || arrived > age) continue;

          const key = y * columns + x;
          const attenuation = Math.max(0, 1 - distance / maxRadius);
          const energy = Math.exp(-age / coolingTime) * attenuation;
          if (energy < .008) continue;
          const cell = cells.get(key) || {
            x,
            y,
            energy: 0,
            hits: 0,
            hueX: 0,
            hueY: 0,
          };
          cell.energy += energy;
          cell.hits++;
          cell.hueX += Math.cos(wave.hue * Math.PI / 180) * energy;
          cell.hueY += Math.sin(wave.hue * Math.PI / 180) * energy;
          cells.set(key, cell);
        }
      }
    }

    const heatGlyphs = [":", "+", "*", "x", "o", "O", "#", "%", "@"]; 
    for (const cell of cells.values()) {
      const heat = Math.min(1, cell.energy);
      const isCool = heat < .08;
      const index = Math.min(
        heatGlyphs.length - 1,
        Math.floor(heat * heatGlyphs.length)
      );
      const hue = (Math.atan2(cell.hueY, cell.hueX) * 180 / Math.PI + 360) % 360;
      const saturation = Math.min(100, 58 + heat * 35 + cell.hits * 4);
      const lightness = dark.matches
        ? Math.min(88, 42 + heat * 42)
        : Math.max(20, 68 - heat * 45);
      context.fillStyle = isCool
        ? dark.matches ? "#686868" : "#aaa"
        : `hsl(${hue} ${saturation}% ${lightness}%)`;
      context.globalAlpha = isCool ? .3 + heat * 2.5 : .2 + heat * .8;
      context.fillText(isCool ? ":" : heatGlyphs[index], cell.x * cellWidth, cell.y * cellHeight);
    }
    context.globalAlpha = 1;
    requestAnimationFrame(draw);
  };

  const originalTriggerAttack = Tone.Sampler.prototype.triggerAttack;
  Tone.Sampler.prototype.triggerAttack = function(notes, time, velocity) {
    if (typeof time === "string" && time.startsWith("+")) {
      const at = Tone.Transport.seconds + Number(time.slice(1));
      Tone.Transport.scheduleOnce(audioTime => {
        originalTriggerAttack.call(this, notes, audioTime, velocity);
        Tone.Draw.schedule(() => {
          (Array.isArray(notes) ? notes : [notes]).forEach(strike);
        }, audioTime);
      }, at);
      return this;
    }
    return originalTriggerAttack.call(this, notes, time, velocity);
  };

  const start = async () => {
    toggle.disabled = true;
    toggle.textContent = "Loading…";
    status.textContent = "loading piano";
    await Tone.start();

    try {
      const destination = new Tone.Gain(.72).toDestination();
      const sampleLibrary = { request: async () => ({ "vsco2-piano-mf": samples }) };
      stage = await pieceAisatsana({
        context: Tone.getContext(),
        destination,
        sampleLibrary,
      });
      stage[1]();
      Tone.Transport.start();
      showTitle();
      playing = true;
      toggle.disabled = false;
      toggle.textContent = "Stop";
      status.textContent = "";
    } catch (error) {
      console.error(error);
      toggle.disabled = false;
      toggle.textContent = "Try again";
      status.textContent = "piano could not be loaded";
    }
  };

  toggle.addEventListener("click", async () => {
    if (!stage) {
      await start();
      return;
    }

    if (playing) {
      Tone.Transport.pause();
      playing = false;
      home.hidden = false;
      toggle.textContent = "Begin again";
      return;
    }

    await Tone.start();
    Tone.Transport.start();
    playing = true;
    home.hidden = true;
    toggle.textContent = "Stop";
  });

  addEventListener("resize", resize);
  dark.addEventListener("change", resize);
  resize();
  requestAnimationFrame(draw);
})();
