// Shiori's backgrounds, from annai (another Machiya app, under the same license): a neon city in the rain, drawn
// on a fixed <canvas id="bg">. The city (sky, three skyline layers, lit windows, neon signs, the wet street and its
// reflections) is drawn once per width into an offscreen canvas from a seeded random, so it never jumps; a frame only
// blits it, flickers a few signs, blinks the beacons and moves the scene's extras. The rain is a separate overlay
// (#rainfx). 30 fps cap, device pixels capped at 1.5, paused while the page is hidden; reduced motion draws one still
// frame. No network, no libraries. window.annaiBg.start(scene, words), .stop(), .rain(true | false): the API keeps
// annai's name so the two copies stay easy to compare. `words` are the page's own names for the signs.
(function () {
  "use strict";
  const C = { sky0: "#07081a", sky1: "#141331", sky2: "#2a1840", haze: "#f56cc7", haze2: "#7dcfff",
              far: "#151733", mid: "#10122a", near: "#0a0b1c", street: "#06070f" };
  const NEON = ["#f56cc7", "#7dcfff", "#ff9e64", "#bb9af7", "#73daca", "#ff5f87", "#e0af68"];
  // Tokyo: every sign Japanese, Akihabara after dark: electronics and games, a little food, no bars
  const TECH = ["電気", "電脳", "電子部品", "秋葉原", "ゲーム", "家電", "無線", "中古", "修理", "買取", "映像", "音響", "案内", "ラーメン", "雨"];
  // Shiori's words as kanji (what each one is or means); a word missing here gets no sign in the Japanese and Chinese
  // scenes
  const KANJI = { shiori: "栞", pages: "頁", notes: "手帳", web: "網", smallweb: "小網", code: "符号", media: "媒体" };
  // Seoul: the same city in Hangul: Yongsan's electronics market after dark, a PC bang, a little food
  const KO_TECH = ["전자", "전자상가", "용산", "게임", "피시방", "노래방", "중고", "수리", "카메라", "음향", "편의점", "치킨", "커피", "약국", "안내", "서울", "비"];
  const HANGUL = { shiori: "시오리", pages: "페이지", notes: "노트", web: "웹", smallweb: "작은웹", code: "코드", media: "미디어" };
  // American cities: English neon, the page's words as they are (vertical blade signs stack the letters)
  const US_WORDS = {
    sf: ["NOODLES", "DIMSUM", "TACOS", "ARCADE", "OPEN", "24H", "RAMEN", "COFFEE", "PHO", "TRAIN", "VR", "TECH", "LAUNDRY"],
    la: ["MOTEL", "TACOS", "DONUTS", "24HRS", "PAWN", "PHO", "ARCADE", "RAMEN", "VIDEO", "HOTEL", "BURGERS", "VACANCY"],
    chicago: ["THEATRE", "HOTDOGS", "PIZZA", "DINER", "LOOP", "HOTEL", "RECORDS", "ARCADE", "DELI", "BOWLING", "CINEMA"],
  };
  // Los Angeles, November 2019 (a homage): kanji and English side by side; no real brands
  const BR_WORDS = ["ヌードル", "強力", "電脳", "寿司", "電気", "未来", "人造人間", "NOODLES", "ENHANCE", "OFFWORLD", "DRAGON", "SUSHI", "雨"];
  const CJK_FONT = "'Hiragino Sans','Apple SD Gothic Neo','PingFang TC','PingFang SC','Thonburi','Noto Sans JP','Noto Sans KR','Noto Sans CJK JP','Noto Sans CJK KR','Noto Sans CJK TC','Noto Sans CJK SC','Noto Sans Thai','Yu Gothic','Malgun Gothic','Microsoft JhengHei',system-ui,sans-serif";
  // more cities: each scene's own street words; the page's words as kanji (Chinese cities: the kanji ones without
  // kana), Hangul, or plain Latin
  const MORE_WORDS = {
    hk: ["大押", "茶餐廳", "麻雀", "電器", "金行", "藥房", "冰室", "九龍", "旺角", "香港", "夜市", "粥麵", "海鮮", "車仔麵"],
    sh: ["上海", "外滩", "电器", "小吃", "面馆", "饭店", "咖啡", "书店", "网吧", "夜市", "生煎", "饺子", "浦东"],
    tp: ["夜市", "小吃", "珍珠奶茶", "滷肉飯", "電器", "網咖", "台北", "牛肉麵", "藥局", "鹹酥雞", "豆花", "便當"],
    sg: ["HAWKER", "SATAY", "LAKSA", "KOPI", "美食", "咖啡", "PRATA", "NASI", "TEH", "CHILLI", "HOTEL", "METRO"],
    lv: ["CASINO", "MOTEL", "WEDDING", "BUFFET", "SLOTS", "24HR", "VACANCY", "SHOWS", "KENO", "POKER", "CHAPEL", "JACKPOT"],
    bkk: ["金行", "餐廳", "藥房", "燕窩", "魚翅", "茶行", "旅社", "唐人街"],
    akira: ["ネオ東京", "暴走族", "未来", "警察", "電脳", "実験", "再開発", "カプセル", "東京", "工事中", "立入禁止"],
    osaka: ["たこ焼き", "お好み焼き", "串カツ", "ラーメン", "道頓堀", "大阪", "くいだおれ", "かに", "うどん", "ふぐ", "焼肉"],
    stray: ["SLUMS", "LAUNDRY", "REPAIR", "PARTS", "NOODLES", "CLINIC", "BATTERY", "SHOP", "99", "MIDTOWN", "TAILOR"],
  };
  const THAI = ["ร้านทอง", "ก๋วยเตี๋ยว", "โรงแรม", "ตลาด", "เยาวราช", "กาแฟ", "ข้าวมันไก่", "อาหาร", "กรุงเทพ"];
  const LATIN_FONT = "'Futura','Avenir Next Condensed','DIN Condensed','Arial Narrow','Roboto Condensed','Helvetica Neue',Arial,sans-serif";
  let SIGNS = TECH, HSIGNS = TECH;     // start(mode, words) mixes in the page's words; HSIGNS: horizontal facade boards
  let beacons = [];
  // the city's front-row windows that are lit (only the front row: nothing is drawn over it, so painting one dark never
  // covers another building), and the ones someone has switched off for now
  let wins = [], dark = [], nextDark = 0;
  let canvas, ctx, city, signs = [], raf = 0, last = 0, mode = null, W = 0, H = 0, horizon = 0, dpr = 1;

  // signs never overlap: a new one whose box, plus a small gap, touches one already placed is left out
  function clear(x, y, w, h) {
    const p = 4 * dpr;
    return !signs.some((o) => x < o.x + o.w + p && x + w + p > o.x && y < o.y + o.h + p && y + h + p > o.y);
  }

  function rng(seed) {            // mulberry32
    return function () { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
  }


  // ---- "Tokyo alley": a street-level view down a narrow Tokyo street in the rain, one-point perspective (the Ginza
  // gas-lamp street at night), crowded with Ueno/Taito-style signs: white lightbox signs and neon ones sticking out
  // from both walls, red lanterns under the eaves, glowing shop windows, gas lamps, a wet brick road that mirrors it all.
  // World units: the street runs along depth d (camera at 0), walls at X = -hw and +hw, height Y (ground 0).
  let scene = "city";
  const ALLEY_FOOD = ["ラーメン", "焼鳥", "二階", "三階", "珈琲", "定食", "案内"];
  function buildAlley() {
    // the same street engine carries three places: the Tokyo alley, Osaka's Dōtonbori (the road is the canal) and
    // Stray's walled city (a ceiling of pipes for a sky, bulbs strung across, a cat)
    const V = scene;
    city = document.createElement("canvas"); city.width = W; city.height = H;
    const g = city.getContext("2d"), r = rng({ osaka: 20261024, stray: 20220719 }[V] || 20261014);
    signs = []; beacons = []; fore = null; extras = [];
    const vx = W / 2, vy = Math.round(H * 0.6), f = Math.max(W, H) * 0.62, eye = 0.55, hw = W > H ? 1.15 : 0.8;
    horizon = vy;
    const P = (X, Y, d) => [vx + X * f / d, vy + (eye - Y) * f / d];
    const quad = (pts, fill) => { g.fillStyle = fill; g.beginPath(); pts.forEach(([x, y], i) => i ? g.lineTo(x, y) : g.moveTo(x, y)); g.closePath(); g.fill(); };
    // sky: a dark slot between the rooftops, the far end of the street glowing
    let gr = g.createLinearGradient(0, 0, 0, vy);
    if (V === "osaka") { gr.addColorStop(0, "#0a0716"); gr.addColorStop(1, "#2a1238"); }
    else if (V === "stray") { gr.addColorStop(0, "#050608"); gr.addColorStop(1, "#10161a"); }
    else { gr.addColorStop(0, "#030806"); gr.addColorStop(1, "#0b1714"); }
    g.fillStyle = gr; g.fillRect(0, 0, W, H);
    let rg = g.createRadialGradient(vx, vy, 0, vx, vy, W * 0.35);
    if (V === "osaka") { rg.addColorStop(0, "rgba(255,160,200,0.5)"); rg.addColorStop(0.2, "rgba(255,120,80,0.22)"); }
    else if (V === "stray") { rg.addColorStop(0, "rgba(120,255,230,0.35)"); rg.addColorStop(0.2, "rgba(255,120,200,0.15)"); }
    else { rg.addColorStop(0, "rgba(180,240,200,0.55)"); rg.addColorStop(0.15, "rgba(255,190,120,0.25)"); }
    rg.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = rg; g.fillRect(0, 0, W, H);
    if (V === "stray") {                                                  // no sky: the walled city's ceiling of pipes and ducts
      for (let i = 0; i < 14; i++) {
        const y = r() * vy * 0.55, th = (3 + r() * 10) * dpr;
        const pg = g.createLinearGradient(0, y, 0, y + th); pg.addColorStop(0, "#2a3236"); pg.addColorStop(0.5, "#4a565b"); pg.addColorStop(1, "#151a1d");
        g.fillStyle = pg; g.fillRect(0, y, W, th);
      }
    }
    // the road: wet herringbone brick, darker near the walls
    const near = 0.55, far = 60;
    gr = g.createLinearGradient(0, vy, 0, H);
    if (V === "osaka") { gr.addColorStop(0, "#0d1420"); gr.addColorStop(1, "#05080e"); }       // the canal
    else if (V === "stray") { gr.addColorStop(0, "#1a1c1c"); gr.addColorStop(1, "#262624"); }  // wet concrete
    else { gr.addColorStop(0, "#1c0f10"); gr.addColorStop(1, "#2a1416"); }
    quad([P(-hw, 0, near), P(hw, 0, near), P(hw, 0, far), P(-hw, 0, far)], gr);
    if (V === "osaka") for (let d = far; d > near; d *= 0.9) {            // ripples on the canal
      const [, y] = P(0, 0, d); g.fillStyle = "rgba(120,160,220," + (0.03 + r() * 0.05).toFixed(2) + ")"; g.fillRect(0, y, W, Math.max(1, f / d * 0.01));
    }
    if (V === "stray") for (let i = 0; i < 18; i++) {                     // puddles catching the neon
      const d = 1.5 + r() * 20, X = (r() * 2 - 1) * hw * 0.8, [x, y] = P(X, 0, d), w = f / d * (0.3 + r() * 0.6);
      g.fillStyle = "rgba(120,220,210,0.08)"; g.beginPath(); g.ellipse(x, y, w, w * 0.12, 0, 0, Math.PI * 2); g.fill();
    }
    if (V === "alley") for (let d = far; d > near; d *= 0.93) {           // brick courses, closer together far away
      const [, y] = P(0, 0, d);
      g.fillStyle = "rgba(10,4,5," + (0.25 + r() * 0.25).toFixed(2) + ")"; g.fillRect(0, y, W, Math.max(1, f / d * 0.012));
      for (let i = 0; i < 6; i++) {                                         // a few lit bricks catching the light
        const X = (r() * 2 - 1) * hw, [x] = P(X, 0, d);
        g.fillStyle = "rgba(255,200,170," + (0.04 + r() * 0.06).toFixed(2) + ")"; g.fillRect(x, y, f / d * 0.06, Math.max(1, f / d * 0.012));
      }
    }
    if (V === "alley") {
      for (const X of [-hw * 0.72, hw * 0.72]) {                            // the white lane lines
        quad([P(X - 0.03, 0, near), P(X + 0.03, 0, near), P(X + 0.03, 0, far), P(X - 0.03, 0, far)], "rgba(235,232,225,0.75)");
      }
      roadText(g, "止まれ", 2.6, P, f);
    }
    // the buildings: one segment after another down each side, far to near
    const segs = [];
    for (const side of [-1, 1]) {
      let d = far;
      while (d > 1.25) {
        const len = 1.6 + r() * 3.2, d0 = Math.max(1.25, d - len), h = 7 + r() * 14;
        segs.push({ side, d0, d1: d, h, tone: r(), shop: r() < 0.75, shopCol: ["#ff3b2f", "#ffb35c", "#f4f1e0", "#9cf0c8", "#ff7aa8"][Math.floor(r() * 5)], lant: r() < 0.45 });
        d = d0 - 0.15;
      }
    }
    segs.sort((a, b) => b.d1 - a.d1);
    for (const sg of segs) {
      const X = sg.side * hw;
      const wall = ["#2b2e36", "#3a2a28", "#2a3130", "#34302b", "#262833"][Math.floor(sg.tone * 5)];
      quad([P(X, 0, sg.d0), P(X, 0, sg.d1), P(X, sg.h, sg.d1), P(X, sg.h, sg.d0)], wall);
      // the facade's near edge, lit from the street
      quad([P(X, 0, sg.d0), P(X + sg.side * 0.25, 0, sg.d0), P(X + sg.side * 0.25, sg.h, sg.d0), P(X, sg.h, sg.d0)], shade(wall, 0.18));
      // windows: lit offices above (greenish white, as in the photo), floor by floor
      const near = (d) => Math.max(0.3, Math.min(1, (d - 1.2) / 3));      // details right beside the camera stay dim
      for (let Y = 1.5; Y < sg.h - 0.5; Y += 0.85)
        for (let d = sg.d0 + 0.2; d < sg.d1 - 0.35; d += 0.6) {
          if (r() < 0.35) continue;
          const col = r() < 0.7 ? "rgba(214,245,205," : "rgba(255,226,170,";
          quad([P(X, Y, d), P(X, Y, d + 0.36), P(X, Y + 0.45, d + 0.36), P(X, Y + 0.45, d)], col + ((0.3 + r() * 0.5) * near(d)).toFixed(2) + ")");
        }
      if (V === "stray") {                                                // AC units and pipes cluttering the walls
        for (let k = 0; k < 6; k++) {
          const d = sg.d0 + 0.2 + r() * Math.max(0.1, sg.d1 - sg.d0 - 0.6), Y = 1.4 + r() * (sg.h - 2);
          quad([P(X, Y, d), P(X, Y, d + 0.45), P(X - sg.side * 0.3, Y, d + 0.45), P(X - sg.side * 0.3, Y, d)], "#3a4246");
          quad([P(X - sg.side * 0.3, Y, d), P(X - sg.side * 0.3, Y, d + 0.45), P(X - sg.side * 0.3, Y + 0.35, d + 0.45), P(X - sg.side * 0.3, Y + 0.35, d)], "#566064");
        }
        const Yp = 2 + r() * (sg.h - 3);
        quad([P(X - sg.side * 0.05, Yp, sg.d0), P(X - sg.side * 0.05, Yp, sg.d1), P(X - sg.side * 0.05, Yp + 0.12, sg.d1), P(X - sg.side * 0.05, Yp + 0.12, sg.d0)], "#5b6468");
      }
      // the shop front at street level, glowing, with its reflection on the wet road
      if (sg.shop) {
        for (let d = sg.d0 + 0.25; d < sg.d1 - 0.3; d += 1.1) {               // shop windows, one per bay
          const d1 = Math.min(sg.d1 - 0.3, d + 0.8);
          quad([P(X, 0.08, d), P(X, 0.08, d1), P(X, 0.78, d1), P(X, 0.78, d)], hexA(sg.shopCol, 0.75 * near(d)));
        }
        quad([P(X * 0.999, 0, sg.d0 + 0.3), P(X * 0.999, 0, sg.d1 - 0.3), P(X * 0.82, 0, sg.d1 - 0.3), P(X * 0.82, 0, sg.d0 + 0.3)], hexA(sg.shopCol, 0.07));
      }
      // red paper lanterns under the eaves
      if (sg.lant) for (let d = sg.d0 + 0.3; d < sg.d1 - 0.2; d += 0.45) {
        const [x, y] = P(X + sg.side * -0.12, 1.25, d), rr = f / d * 0.07;
        g.save(); g.shadowColor = "#ff5a3c"; g.shadowBlur = rr * 2.5; g.fillStyle = "#ff4b33";
        g.beginPath(); g.ellipse(x, y, rr * 0.75, rr, 0, 0, Math.PI * 2); g.fill(); g.restore();
        g.fillStyle = "rgba(255,210,170,0.6)"; g.fillRect(x - rr * 0.75, y - rr * 0.08, rr * 1.5, Math.max(1, rr * 0.16));
      }
      // signs on this segment: lightboxes and neon, sticking out from the wall into the street, stacked
      const count = 2 + Math.floor(r() * 4);
      for (let i = 0; i < count; i++) {
        const d = sg.d0 + 0.2 + r() * Math.max(0.1, sg.d1 - sg.d0 - 0.4), text = SIGNS[Math.floor(r() * SIGNS.length)], n = [...text].length;
        const depthOut = 0.18 + r() * 0.08, sh = Math.min(n * 0.36 + 0.3, 2.6), Y1 = 1.3 + r() * Math.max(0.2, Math.min(sg.h, 9) - sh - 1.4);
        const [x0, yTop] = P(X, Y1 + sh, d), [x1, yBot] = P(X - sg.side * depthOut, Y1, d);
        const w = Math.abs(x1 - x0), fs = Math.min(w * 0.62, (yBot - yTop) / (n * 1.08 + 0.6));
        if (fs < 4 || yBot > H || yTop < 0) continue;
        if (!clear(Math.min(x0, x1), yTop, w, yBot - yTop)) continue;
        const light = r() < 0.7;
        signs.push({ text, vertical: true, fs, x: Math.min(x0, x1), y: yTop, w, h: yBot - yTop, d, lightbox: light,
                     col: light ? (r() < 0.35 ? "#c8202c" : "#16161e") : NEON[Math.floor(r() * NEON.length)],
                     flick: r() < 0.18, dead: r() < 0.15 ? Math.floor(r() * n) : -1, next: 0, burstEnd: 0, glow: Math.min(1, 6 / d) });
      }
    }
    if (V === "osaka") {                                                  // a bridge over the canal, its railing lit
      for (const d of [9, 26]) {
        const [xl, yl] = P(-hw, 1.2, d), [xr] = P(hw, 1.2, d), [, ya] = P(0, 2.0, d), [, yb] = P(0, 0.2, d);
        g.fillStyle = "#1a1420"; g.beginPath(); g.moveTo(xl, yb); g.quadraticCurveTo((xl + xr) / 2, ya - (yb - ya) * 0.3, xr, yb);
        g.lineTo(xr, yl); g.quadraticCurveTo((xl + xr) / 2, ya - (yl - ya) * 0.8, xl, yl); g.fill();
        g.save(); g.shadowColor = "#ffd28a"; g.shadowBlur = f / d * 0.1; g.fillStyle = "rgba(255,226,170,0.9)";
        for (let k = 0; k <= 16; k++) { const tt = k / 16, x = xl + (xr - xl) * tt, y = yl - (yl - ya) * 0.8 * 4 * tt * (1 - tt) * 0.5; g.fillRect(x, y - f / d * 0.02, f / d * 0.04, f / d * 0.04); }
        g.restore();
      }
    }
    if (V === "stray") {                                                  // bulbs strung across between the walls
      for (let d = 3; d < far * 0.5; d += 4.2) {
        const [xl, y0] = P(-hw, 6, d), [xr] = P(hw, 6, d), sag = f / d * 0.6;
        g.strokeStyle = "rgba(20,24,26,0.9)"; g.lineWidth = Math.max(1, f / d * 0.01); g.beginPath(); g.moveTo(xl, y0); g.quadraticCurveTo((xl + xr) / 2, y0 + sag * 2, xr, y0); g.stroke();
        g.save(); g.shadowColor = "#ffcf7a"; g.shadowBlur = f / d * 0.15; g.fillStyle = "#ffe2a8";
        for (let k = 1; k < 10; k++) { const tt = k / 10, x = xl + (xr - xl) * tt, y = y0 + sag * 4 * tt * (1 - tt); g.beginPath(); g.arc(x, y + f / d * 0.03, Math.max(1, f / d * 0.025), 0, Math.PI * 2); g.fill(); }
        g.restore();
      }
      const [cx0, cy] = P(-hw * 0.9, 0, 3.4), [cx1] = P(hw * 0.9, 0, 3.4);  // the cat crossing (drawn per frame)
      extras.push({ kind: "cat", x0: cx0, x1: cx1, y: cy, s: f / 3.4 * 0.22, period: 26000 });
    }
    // gas lamps down the right side, warm pools of light on the bricks
    if (V === "alley") for (let d = 3.2; d < far * 0.6; d += 3.6) {
      const X = hw * 0.88, [px, py0] = P(X, 0, d), [, py1] = P(X, 2.1, d), lw = Math.max(1, f / d * 0.03);
      rg = g.createRadialGradient(px, py0, 0, px, py0, f / d * 0.9);
      rg.addColorStop(0, "rgba(255,214,150,0.22)"); rg.addColorStop(1, "rgba(255,214,150,0)");
      g.fillStyle = rg; g.fillRect(px - f / d, py0 - f / d * 0.4, f / d * 2, f / d * 0.8);
      g.fillStyle = "#1e3b33"; g.fillRect(px - lw / 2, py1, lw, py0 - py1);
      g.save(); g.shadowColor = "#ffd28a"; g.shadowBlur = f / d * 0.3; g.fillStyle = "#fff0c8";
      g.fillRect(px - lw * 2.2, py1 - lw * 4, lw * 4.4, lw * 4); g.restore();
    }
    signs.sort((a, b) => b.d - a.d);                                         // far signs first: near ones cover them
    // every sign mirrored in the wet road, broken into ripples
    for (const sg of signs) {
      const gy = vy + eye * f / sg.d, top = gy + (gy - (sg.y + sg.h)), len = sg.h * 0.9;
      for (let y = top; y < Math.min(H, top + len); y += (2 + r() * 3) * dpr) {
        g.fillStyle = hexA(sg.lightbox ? "#f4f1e8" : sg.col, (0.05 + r() * 0.18) * (1 - (y - top) / len));
        g.fillRect(sg.x + (r() - 0.5) * sg.w * 0.3, y, sg.w * (0.6 + r() * 0.5), Math.max(1, (1 + r() * 2) * dpr));
      }
    }
  }
  function roadText(g, text, d, P, f) {                                    // a marking painted flat on the road
    const chars = [...text];
    chars.forEach((ch, i) => {
      const dd = d + i * 1.0, [x, y] = P(0, 0, dd), size = f / dd * 0.5;
      g.save(); g.translate(x, y); g.scale(1, 0.32); g.fillStyle = "rgba(235,232,225,0.7)";
      g.font = "700 " + Math.round(size) + "px " + FONT; g.textAlign = "center"; g.textBaseline = "middle";
      g.fillText(ch, 0, 0); g.restore();
    });
  }
  function shade(hex, k) {
    const n = parseInt(hex.slice(1), 16), c = (v) => Math.min(255, Math.round(v + (255 - v) * k));
    return "rgb(" + c(n >> 16 & 255) + "," + c(n >> 8 & 255) + "," + c(n & 255) + ")";
  }

  function buildCity() {
    city = document.createElement("canvas"); city.width = W; city.height = H;
    const g = city.getContext("2d"), r = rng({ seoul: 20261014, sf: 20261015, la: 20261016, chicago: 20261017, br: 20191101, hk: 20261018, sh: 20261019, tp: 20261020,
                                                  sg: 20261021, lv: 20261022, bkk: 20261023, akira: 20190716 }[scene] || 20261013);
    fore = null; extras = []; beacons = [];
    horizon = Math.round(H * 0.74);
    // sky
    let s = g.createLinearGradient(0, 0, 0, horizon);
    s.addColorStop(0, C.sky0); s.addColorStop(0.55, C.sky1); s.addColorStop(1, C.sky2);
    g.fillStyle = s; g.fillRect(0, 0, W, horizon);
    // city glow on the low clouds
    for (const [x, col, a] of [[0.25, C.haze, 0.22], [0.7, C.haze2, 0.16], [0.5, "#ff9e64", 0.10]]) {
      const rg = g.createRadialGradient(W * x, horizon, 0, W * x, horizon, W * 0.6);
      rg.addColorStop(0, hexA(col, a)); rg.addColorStop(1, hexA(col, 0));
      g.fillStyle = rg; g.fillRect(0, 0, W, horizon);
    }
    if (scene === "akira") {                                              // Neo-Tokyo: a red night over the rebuilt city
      const sm = g.createLinearGradient(0, 0, 0, horizon);
      sm.addColorStop(0, "rgba(10,4,8,0.8)"); sm.addColorStop(1, "rgba(120,20,30,0.5)");
      g.fillStyle = sm; g.fillRect(0, 0, W, horizon);
    }
    if (scene === "lv") {                                                 // the Strip's glow on the desert sky
      const sm = g.createLinearGradient(0, 0, 0, horizon);
      sm.addColorStop(0, "rgba(10,6,20,0.5)"); sm.addColorStop(1, "rgba(255,120,60,0.28)");
      g.fillStyle = sm; g.fillRect(0, 0, W, horizon);
    }
    if (scene === "br") {                                                // smog lit from below by the fires: rust and brown
      const sm = g.createLinearGradient(0, 0, 0, horizon);
      sm.addColorStop(0, "rgba(8,6,12,0.85)"); sm.addColorStop(0.6, "rgba(60,30,25,0.55)"); sm.addColorStop(1, "rgba(150,70,35,0.55)");
      g.fillStyle = sm; g.fillRect(0, 0, W, horizon);
    }
    // three skyline layers, back to front
    signs = []; wins = []; dark = []; nextDark = 0;
    if (scene === "seoul") {
      ridges(g, r);                                                       // Bukhansan's ridges ring the city
      layer(g, r, C.far, horizon, H * 0.16, H * 0.36, 0.012, 0.35, 0);
      landmarks(g, "hilltower");                                             // the tower on its wooded hill, behind the middle row
      landmarks(g, "tallglass");
      layer(g, r, C.mid, horizon, H * 0.12, H * 0.33, 0.03, 0.6, 0.35);
      layer(g, r, C.near, horizon, H * 0.06, H * 0.22, 0.05, 0.9, 0.85);
    } else if (scene === "sf") {
      ridges(g, r, [["#272b54", 0.44, 0.06], ["#1f2348", 0.3, 0.05]]);   // Twin Peaks and the hills
      landmarks(g, "mast");
      layer(g, r, C.far, horizon, H * 0.14, H * 0.32, 0.012, 0.35, 0);
      landmarks(g, "obelisk"); landmarks(g, "spike");
      layer(g, r, C.mid, horizon, H * 0.1, H * 0.28, 0.03, 0.6, 0.35);
      fogBand(g);                                                          // the fog, low among the towers
      layer(g, r, C.near, horizon, H * 0.06, H * 0.2, 0.05, 0.9, 0.85);
    } else if (scene === "la") {
      ridges(g, r, [["#2c2547", 0.36, 0.05], ["#221d3c", 0.24, 0.04]]);   // the San Gabriels behind the basin
      layer(g, r, C.far, horizon, H * 0.12, H * 0.28, 0.012, 0.35, 0);
      landmarks(g, "sail"); landmarks(g, "crown");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.24, 0.03, 0.6, 0.35);
      layer(g, r, C.near, horizon, H * 0.05, H * 0.17, 0.05, 0.9, 0.85);
    } else if (scene === "br") {
      hades(g, r);                                                         // the industrial sprawl to the horizon
      layer(g, r, "#120f1f", horizon, H * 0.12, H * 0.3, 0.02, 0.35, 0);
      landmarks(g, "arcology");                                             // in front of the far towers: they dominate the sky
      layer(g, r, "#0e0c1a", horizon, H * 0.12, H * 0.34, 0.035, 0.6, 0.4);
      landmarks(g, "geisha");                                             // her screen is on one of the city's towers
      layer(g, r, "#09080f", horizon, H * 0.06, H * 0.24, 0.05, 0.9, 0.9);
    } else if (scene === "hk") {
      ridges(g, r, [["#1c2b3a", 0.66, 0.08], ["#152230", 0.5, 0.06]]);   // Victoria Peak behind the island
      layer(g, r, C.far, horizon, H * 0.18, H * 0.4, 0.015, 0.35, 0);
      landmarks(g, "fins"); landmarks(g, "prism");
      layer(g, r, C.mid, horizon, H * 0.14, H * 0.36, 0.035, 0.6, 0.5);
      layer(g, r, C.near, horizon, H * 0.08, H * 0.26, 0.05, 0.9, 0.95);
    } else if (scene === "sh") {
      layer(g, r, C.far, horizon, H * 0.1, H * 0.26, 0.012, 0.35, 0);
      landmarks(g, "spheres"); landmarks(g, "pagoda"); landmarks(g, "opener"); landmarks(g, "twist");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.22, 0.03, 0.6, 0.35);
      layer(g, r, C.near, horizon, H * 0.05, H * 0.16, 0.05, 0.9, 0.85);
    } else if (scene === "tp") {
      ridges(g, r, [["#1b2a35", 0.5, 0.07], ["#14212b", 0.36, 0.05]]);   // Yangmingshan
      layer(g, r, C.far, horizon, H * 0.1, H * 0.24, 0.012, 0.35, 0);
      landmarks(g, "bamboo");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.2, 0.03, 0.6, 0.4);
      layer(g, r, C.near, horizon, H * 0.05, H * 0.16, 0.05, 0.9, 0.95);
    } else if (scene === "sg") {
      layer(g, r, C.far, horizon, H * 0.14, H * 0.34, 0.015, 0.35, 0);
      landmarks(g, "skypark");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.24, 0.03, 0.6, 0.3);
      layer(g, r, C.near, horizon, H * 0.05, H * 0.15, 0.05, 0.9, 0.7);
    } else if (scene === "lv") {
      ridges(g, r, [["#3a2440", 0.4, 0.06], ["#2b1c33", 0.28, 0.05]]);   // the Spring Mountains, desert purple
      layer(g, r, C.far, horizon, H * 0.1, H * 0.26, 0.015, 0.35, 0);
      landmarks(g, "pyramid"); landmarks(g, "needle"); landmarks(g, "orb");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.22, 0.03, 0.6, 0.6);
      layer(g, r, C.near, horizon, H * 0.05, H * 0.17, 0.05, 0.9, 1);
    } else if (scene === "bkk") {
      layer(g, r, C.far, horizon, H * 0.12, H * 0.3, 0.012, 0.35, 0);
      landmarks(g, "rings"); landmarks(g, "pixels");
      layer(g, r, C.mid, horizon, H * 0.08, H * 0.22, 0.03, 0.6, 0.5);
      layer(g, r, C.near, horizon, H * 0.06, H * 0.2, 0.05, 0.9, 1);
    } else if (scene === "akira") {
      layer(g, r, "#120c14", horizon, H * 0.16, H * 0.38, 0.015, 0.35, 0);
      landmarks(g, "neotower");
      layer(g, r, "#0d0a12", horizon, H * 0.12, H * 0.3, 0.035, 0.6, 0.4);
      layer(g, r, "#08070c", horizon, H * 0.06, H * 0.2, 0.05, 0.9, 0.8);
    } else if (scene === "chicago") {
      layer(g, r, C.far, horizon, H * 0.16, H * 0.36, 0.012, 0.35, 0);
      landmarks(g, "tubes"); landmarks(g, "braced"); landmarks(g, "frustums");
      layer(g, r, C.mid, horizon, H * 0.12, H * 0.3, 0.03, 0.6, 0.35);
      landmarks(g, "cobs");
      layer(g, r, C.near, horizon, H * 0.06, H * 0.2, 0.05, 0.9, 0.85);
    } else {
    layer(g, r, C.far, horizon, H * 0.18, H * 0.42, 0.012, 0.35, 0);
    landmarks(g, "spire");
    layer(g, r, C.mid, horizon, H * 0.12, H * 0.33, 0.03, 0.6, 0.35);
    landmarks(g, "tower");                                                // in front of the middle buildings, behind the street
    layer(g, r, C.near, horizon, H * 0.06, H * 0.22, 0.05, 0.9, 0.85);
    }
    // the street mirrors the city: the skyline flipped, faint, cut into ripples by the rain
    const band = Math.round(H * 0.42), mir = Math.min(band, H - horizon);
    g.save(); g.globalAlpha = 0.22; g.translate(0, horizon * 2); g.scale(1, -1);
    g.drawImage(city, 0, horizon - mir, W, mir, 0, horizon - mir, W, mir); g.restore();
    // the wet street
    s = g.createLinearGradient(0, horizon, 0, H);
    s.addColorStop(0, "rgba(13,14,32,0.55)"); s.addColorStop(1, "rgba(6,7,15,0.92)");
    g.fillStyle = s; g.fillRect(0, horizon, W, H - horizon);
    for (let y = horizon + 3 * dpr; y < H; y += (3 + r() * 5) * dpr) {        // ripple lines across the wet road
      g.fillStyle = "rgba(6,7,15," + (0.25 + r() * 0.35).toFixed(2) + ")"; g.fillRect(0, y, W, (1 + r() * 2) * dpr);
    }
    // reflections: each sign's colour smeared down the wet street
    for (const sg of signs) {
      if (sg.block) continue;
      const depth = Math.min(H - horizon, (sg.h + (horizon - sg.y) * 0.6) * 1.1);
      for (let y = horizon + 2 * dpr; y < horizon + depth; y += (2 + r() * 4) * dpr) {
        const k = 1 - (y - horizon) / depth, jit = (r() - 0.5) * sg.w * 0.5;
        g.fillStyle = hexA(sg.col, (0.08 + r() * 0.32) * k * sg.glow);
        g.fillRect(sg.x + jit - sg.w * 0.1, y, sg.w * (0.6 + r() * 0.7), (1 + r() * 2.5) * dpr);
      }
    }
    if (scene === "akira") {                                              // the crater in the bay, its rim ringed with lights
      const cx = W * 0.5, cy = horizon + (H - horizon) * 0.06, cw = W * (W > H ? 0.42 : 0.8), ch = (H - horizon) * 0.32, u = Math.min(W, H * 1.2) / 100;
      g.fillStyle = "#030205"; g.beginPath(); g.ellipse(cx, cy, cw / 2, ch / 2, 0, 0, Math.PI * 2); g.fill();
      g.strokeStyle = "rgba(255,90,70,0.35)"; g.lineWidth = Math.max(1, u * 0.2); g.beginPath(); g.ellipse(cx, cy, cw / 2, ch / 2, 0, 0, Math.PI * 2); g.stroke();
      for (let a = 0; a < Math.PI * 2; a += 0.09) { g.fillStyle = "rgba(255,200,150,0.7)"; g.fillRect(cx + Math.cos(a) * cw / 2, cy + Math.sin(a) * ch / 2, u * 0.25, u * 0.25); }
    }
    if (scene === "seoul") {                                              // a bridge over the Han: deck, piers, its lamps
      const by = horizon + (H - horizon) * 0.16, u = Math.min(W, H * 1.2) / 100;
      g.fillStyle = "#0b0d1f"; g.fillRect(0, by, W, u * 0.9);
      for (let x = W * 0.04; x < W; x += W * 0.09) g.fillRect(x, by, u * 0.8, (H - by) * 0.5);
      g.save(); g.shadowColor = "#e0af68"; g.shadowBlur = u;
      for (let x = u; x < W; x += u * 2.4) { g.fillStyle = "rgba(255,214,150,0.85)"; g.fillRect(x, by - u * 0.25, u * 0.35, u * 0.25); }
      g.restore();
    }
    // street-light pools and a road line
    for (let i = 0; i < 5; i++) {
      const x = W * (0.1 + 0.2 * i + (r() - 0.5) * 0.06), rg = g.createRadialGradient(x, horizon + (H - horizon) * 0.35, 0, x, horizon + (H - horizon) * 0.35, W * 0.12);
      rg.addColorStop(0, "rgba(224,175,104,0.10)"); rg.addColorStop(1, "rgba(224,175,104,0)");
      g.fillStyle = rg; g.fillRect(0, horizon, W, H - horizon);
    }
    g.fillStyle = "rgba(192,202,245,0.06)"; g.fillRect(0, horizon + 2, W, 2);
    if (["sf", "la", "chicago", "br", "hk", "sh", "tp", "sg", "lv", "bkk", "akira"].includes(scene)) buildFore(r);
  }

  // ---- the American cities: what stands in front of the signs (drawn after them every frame) and what moves
  let fore = null, extras = [];
  const U = () => Math.min(W, H * 1.2) / 100;
  function buildFore(r) {
    fore = document.createElement("canvas"); fore.width = W; fore.height = H;
    const g = fore.getContext("2d"), u = U();
    if (scene === "sf") {                                                 // the Golden Gate, lower left, over the water
      const deck = horizon + (H - horizon) * 0.1, x1 = W * 0.07, x2 = W * (W > H ? 0.33 : 0.55), top = deck - Math.min(horizon * 0.5, H * 0.36);
      g.save(); g.shadowColor = "#ff6b4a"; g.shadowBlur = u * 1.2; g.strokeStyle = "#c63a2b"; g.fillStyle = "#c63a2b";
      for (const tx of [x1, x2]) {
        g.fillRect(tx - u * 0.9, top, u * 0.5, deck - top + (H - deck) * 0.3); g.fillRect(tx + u * 0.4, top, u * 0.5, deck - top + (H - deck) * 0.3);
        for (const k of [0.04, 0.3, 0.55, 0.78]) g.fillRect(tx - u * 0.9, top + (deck - top) * k, u * 1.8, u * 0.45);
      }
      g.lineWidth = Math.max(1, u * 0.25); g.beginPath();                  // main cables: shore to tower, sag, tower to beyond
      g.moveTo(-W * 0.05, deck - u); g.quadraticCurveTo((x1 - W * 0.05) / 2, deck - u * 2, x1, top);
      g.quadraticCurveTo((x1 + x2) / 2, deck + (top - deck) * 0.05, x2, top);
      g.quadraticCurveTo(x2 + (x2 - x1) * 0.4, deck - (deck - top) * 0.2, x2 + (x2 - x1) * 0.8, deck - u); g.stroke();
      g.shadowBlur = 0; g.lineWidth = Math.max(1, u * 0.06); g.globalAlpha = 0.7;
      for (let x = x1 + u; x < x2; x += u * 1.1) {                         // suspenders hanging from the main span
        const k = (x - x1) / (x2 - x1), cy = top + (deck - top) * (1 - 4 * (k - 0.5) * (k - 0.5)) * 0.95;
        g.beginPath(); g.moveTo(x, cy); g.lineTo(x, deck); g.stroke();
      }
      g.globalAlpha = 1; g.fillStyle = "#8f2a20"; g.fillRect(-W * 0.05, deck, x2 + (x2 - x1) * 0.9 + W * 0.05, u * 0.8);   // the deck
      g.fillStyle = "rgba(255,214,150,0.9)"; for (let x = 0; x < x2 + (x2 - x1) * 0.8; x += u * 1.8) g.fillRect(x, deck - u * 0.3, u * 0.3, u * 0.25);
      g.restore();
      beacons.push({ x: x1 - u * 0.65, y: top - u * 0.3, r: u * 0.3 }, { x: x1 + u * 0.65, y: top - u * 0.3, r: u * 0.3 },
                   { x: x2 - u * 0.65, y: top - u * 0.3, r: u * 0.3 }, { x: x2 + u * 0.65, y: top - u * 0.3, r: u * 0.3 });
    }
    if (scene === "la") {                                                 // palm silhouettes along the street, refinery flares far off
      const n = Math.max(6, Math.round(W / (u * 7)));
      for (let i = 0; i < n; i++) {
        const x = (i + 0.3 + r() * 0.4) * W / n, hgt = Math.min(horizon * (0.42 + r() * 0.18), H * 0.42) * 0.25, lean = (r() - 0.5) * u, top = horizon - hgt;
        g.strokeStyle = "#06070e"; g.lineWidth = Math.max(1, u * 0.12);   // a quarter of the first size
        g.beginPath(); g.moveTo(x, horizon + u); g.quadraticCurveTo(x + lean * 0.3, horizon - hgt * 0.5, x + lean, top); g.stroke();
        g.fillStyle = "#06070e";
        for (let k = 0; k < 9; k++) {                                     // fronds: drooping leaves round the crown
          const a = (k / 9) * Math.PI * 2, len = u * (0.8 + r() * 0.4), ex = x + lean + Math.cos(a) * len, ey = top + Math.abs(Math.sin(a)) * len * 0.35 + len * 0.25;
          g.beginPath(); g.moveTo(x + lean, top); g.quadraticCurveTo(x + lean + Math.cos(a) * len * 0.6, top - len * 0.35, ex, ey);
          g.quadraticCurveTo(x + lean + Math.cos(a) * len * 0.5, top - len * 0.15, x + lean, top + u * 0.08); g.fill();
        }
      }
      for (const fx of [W * 0.04, W * 0.95]) {                             // the stacks; their flames are drawn per frame
        g.fillStyle = "#0c0d1c"; g.fillRect(fx - u * 0.35, horizon - horizon * 0.2, u * 0.7, horizon * 0.2);
        extras.push({ kind: "flare", x: fx, y: horizon - horizon * 0.2, s: u * 1.8 });
      }
    }
    if (scene === "br") {                                                 // the advertising blimp and spinners in the sky (no fire)
      extras.push({ kind: "blimp", y: H * (W > H ? 0.16 : 0.12), L: Math.max(W * 0.16, u * 16), u, period: 150000 });
      for (let i = 0; i < 3; i++) extras.push({ kind: "spinner", y: H * (0.12 + r() * 0.32), speed: 0.03 + r() * 0.05, phase: r() * 60000, dir: r() < 0.5 ? 1 : -1, u: u * (0.6 + r() * 0.6) });
    }
    if (scene === "hk") {                                                 // the ferry crossing the harbour; the light show's lasers
      extras.push({ kind: "boat", y: horizon + (H - horizon) * 0.22, L: Math.max(u * 10, W * 0.08), period: 70000, phase: 20000, ferry: true, u });
    }
    if (scene === "sh") {                                                 // boats on the Huangpu
      extras.push({ kind: "boat", y: horizon + (H - horizon) * 0.14, L: Math.max(u * 12, W * 0.1), period: 90000, phase: 30000, u });
      extras.push({ kind: "boat", y: horizon + (H - horizon) * 0.3, L: Math.max(u * 8, W * 0.07), period: 60000, phase: 0, dir: -1, u });
    }
    if (scene === "tp" || scene === "bkk") {                              // scooters (Taipei) or tuk-tuks (Bangkok) streaming along the street
      extras.push({ kind: "traffic", y: horizon - u * 0.6, u, n: scene === "tp" ? 26 : 12, tuk: scene === "bkk", seed: r() * 1000 });
    }
    if (scene === "sg") {                                                 // the grove of steel trees, lower left, its canopies changing colour
      const trees = [];
      for (let i = 0; i < 6; i++) {
        const x = W * (0.04 + i * (W > H ? 0.05 : 0.09)) + r() * u * 2, ht = Math.min(horizon * (0.22 + r() * 0.14), H * 0.22);
        g.strokeStyle = "#0c1018"; g.lineWidth = u * 0.5; g.beginPath(); g.moveTo(x, horizon + u); g.lineTo(x, horizon - ht); g.stroke();
        trees.push({ x, y: horizon - ht, w: u * (3.5 + r() * 2) });
      }
      extras.push({ kind: "trees", trees, u });
    }
    if (scene === "lv") {                                                 // the pyramid's beam
      extras.push({ kind: "skybeam", x: W * (W > H ? 0.2 : 0.18), y: horizon - Math.min(horizon * 0.32, H * 0.24) });
    }
    if (scene === "akira") {                                              // searchlights over the city, a red bike streaking past
      for (let i = 0; i < 4; i++) extras.push({ kind: "beam", x: W * (0.15 + i * 0.24), y: horizon, a0: -Math.PI / 2 + (r() - 0.5) * 0.6, p: 2600 + i * 900, ph: i * 1.7 });
      extras.push({ kind: "bike", y: horizon + (H - horizon) * 0.03, u, period: 13000 });
    }
    if (scene === "chicago") {                                            // the L: girders on columns across the street
      const ty = horizon - Math.min(horizon * 0.07, H * 0.05);
      g.fillStyle = "#0a0b17"; g.fillRect(0, ty, W, u * 1.1);
      g.strokeStyle = "#0a0b17"; g.lineWidth = Math.max(1, u * 0.18);
      for (let x = 0; x < W; x += u * 1.2) { g.beginPath(); g.moveTo(x, ty + u * 1.1); g.lineTo(x + u * 0.6, ty + u * 2.2); g.lineTo(x + u * 1.2, ty + u * 1.1); g.stroke(); }
      g.fillRect(0, ty + u * 2.1, W, u * 0.4);
      for (let x = u * 2; x < W; x += u * 9) g.fillRect(x, ty + u * 2.4, u * 0.8, horizon - ty - u * 2.4);
      extras.push({ kind: "train", y: ty - u * 2.3, h: u * 2.2, car: u * 9, u });
    }
  }
  function drawExtras(t) {
    for (const e of extras) {
      if (e.kind === "flare") {                                           // a gas flare: steady, now and then a lick of flame
        const k = mode === "rain" ? 0.75 + 0.25 * Math.sin(t / 130 + e.x) + (Math.random() < 0.04 ? 0.6 : 0) : 1;
        const rg = ctx.createRadialGradient(e.x, e.y - e.s * k, 0, e.x, e.y - e.s * k, e.s * 2.2 * k);
        rg.addColorStop(0, "rgba(255,240,200,0.95)"); rg.addColorStop(0.3, "rgba(255,150,60,0.75)"); rg.addColorStop(1, "rgba(255,80,20,0)");
        ctx.fillStyle = rg; ctx.beginPath(); ctx.ellipse(e.x, e.y - e.s * k, e.s * 0.9 * k, e.s * 2 * k, 0, 0, Math.PI * 2); ctx.fill();
      } else if (e.kind === "train") {                                     // a train every 40 s, 14 s to cross
        const period = 40000, cross = 14000, ph = (t % period);
        if (mode !== "rain" || ph > cross) continue;
        const len = e.car * 5, x = -len + (W + len) * (ph / cross);
        for (let c = 0; c < 5; c++) {
          const cx = x + c * e.car;
          ctx.fillStyle = "#3b4060"; ctx.fillRect(cx, e.y, e.car - e.u * 0.3, e.h);
          ctx.fillStyle = "rgba(255,236,190,0.9)";
          for (let w = cx + e.u * 0.6; w < cx + e.car - e.u; w += e.u * 1.4) ctx.fillRect(w, e.y + e.h * 0.25, e.u * 0.8, e.h * 0.35);
        }
      } else if (e.kind === "spinner") {                                   // a spinner crossing the sky, its strobe blinking
        if (mode !== "rain") continue;
        const span = W + 200 * dpr, x = ((t * e.speed + e.phase) % (span * 2.5)) - 100 * dpr;
        if (x > span) continue;
        const px = e.dir > 0 ? x : W - x, y = e.y + Math.sin(t / 900 + e.phase) * 6 * dpr;
        ctx.fillStyle = "#1a1828"; ctx.fillRect(px - e.u * 2, y - e.u * 0.5, e.u * 4, e.u);
        const hl = ctx.createLinearGradient(px, y, px + e.dir * e.u * 14, y + e.u * 3);       // its headlight cone in the rain
        hl.addColorStop(0, "rgba(220,235,255,0.35)"); hl.addColorStop(1, "rgba(220,235,255,0)");
        ctx.fillStyle = hl; ctx.beginPath(); ctx.moveTo(px + e.dir * e.u * 2, y); ctx.lineTo(px + e.dir * e.u * 14, y - e.u * 2); ctx.lineTo(px + e.dir * e.u * 14, y + e.u * 5); ctx.closePath(); ctx.fill();
        if ((t % 900) < 120) { ctx.fillStyle = (t % 1800) < 900 ? "#ff3355" : "#55aaff"; ctx.beginPath(); ctx.arc(px, y - e.u * 0.7, e.u * 0.45, 0, Math.PI * 2); ctx.fill(); }
      } else if (e.kind === "beam") {                                      // the pyramid's searchlights sweeping the smog
        const a = e.a0 + Math.sin(t / e.p + e.ph) * 0.5 * (mode === "rain" ? 1 : 0), len = H * 1.2;
        const gx = e.x + Math.cos(a) * len, gy = e.y + Math.sin(a) * len, w = 0.035;
        const gr = ctx.createLinearGradient(e.x, e.y, gx, gy); gr.addColorStop(0, "rgba(255,240,210,0.16)"); gr.addColorStop(1, "rgba(255,240,210,0)");
        ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(e.x, e.y);
        ctx.lineTo(e.x + Math.cos(a - w) * len, e.y + Math.sin(a - w) * len); ctx.lineTo(e.x + Math.cos(a + w) * len, e.y + Math.sin(a + w) * len); ctx.closePath(); ctx.fill();
      } else if (e.kind === "cat") {                                       // a ginger cat trotting across the street now and then
        const ph = mode === "rain" ? (t % e.period) / e.period : 0.3; if (ph > 0.4) continue;
        const k = ph / 0.4, x = e.x0 + (e.x1 - e.x0) * k, s = e.s, step = Math.sin(t / 90);
        ctx.save(); ctx.fillStyle = "#c8742a"; ctx.translate(x, e.y);
        ctx.beginPath(); ctx.ellipse(0, -s * 0.55, s * 0.55, s * 0.22, 0, 0, Math.PI * 2); ctx.fill();            // body
        ctx.beginPath(); ctx.arc(s * 0.55, -s * 0.78, s * 0.17, 0, Math.PI * 2); ctx.fill();                     // head
        ctx.beginPath(); ctx.moveTo(s * 0.45, -s * 0.9); ctx.lineTo(s * 0.5, -s * 1.08); ctx.lineTo(s * 0.58, -s * 0.92); ctx.fill();   // ears
        ctx.beginPath(); ctx.moveTo(s * 0.6, -s * 0.9); ctx.lineTo(s * 0.68, -s * 1.06); ctx.lineTo(s * 0.72, -s * 0.88); ctx.fill();
        ctx.strokeStyle = "#c8742a"; ctx.lineWidth = s * 0.08; ctx.lineCap = "round";
        ctx.beginPath(); ctx.moveTo(-s * 0.5, -s * 0.6); ctx.quadraticCurveTo(-s * 0.85, -s * 0.9, -s * 0.75, -s * 1.15); ctx.stroke();   // tail up
        for (const [lx, p] of [[-s * 0.35, step], [-s * 0.2, -step], [s * 0.3, -step], [s * 0.42, step]]) {
          ctx.beginPath(); ctx.moveTo(lx, -s * 0.4); ctx.lineTo(lx + p * s * 0.1, 0); ctx.stroke();
        }
        ctx.restore();
      } else if (e.kind === "boat") {                                      // a ferry or a lit boat crossing the water
        const span = W + e.L * 2, dir = e.dir || 1, k = mode === "rain" ? ((t + e.phase) % e.period) / e.period : 0.4;
        const x = dir > 0 ? k * span - e.L : W + e.L - k * span, y = e.y;
        ctx.fillStyle = e.ferry ? "#e8ecef" : "#20253a"; ctx.fillRect(x - e.L / 2, y - e.u * 0.9, e.L, e.u * 0.9);
        ctx.fillStyle = e.ferry ? "#2f7d4f" : "#141826"; ctx.fillRect(x - e.L / 2, y - e.u * 0.25, e.L, e.u * 0.5);
        ctx.fillStyle = "rgba(255,230,170,0.9)"; for (let w = x - e.L / 2 + e.u * 0.6; w < x + e.L / 2 - e.u * 0.5; w += e.u * 1.1) ctx.fillRect(w, y - e.u * 0.7, e.u * 0.55, e.u * 0.35);
        ctx.fillStyle = "rgba(255,230,170,0.12)"; ctx.fillRect(x - e.L / 2, y + e.u * 0.3, e.L, e.u * 2.5);       // its reflection
      } else if (e.kind === "traffic") {                                   // streams of small headlights and tail lights
        if (mode !== "rain") continue;
        for (let i = 0; i < e.n; i++) {
          const sp = 0.05 + ((i * 37 + e.seed) % 10) / 120, dir = i % 2 ? 1 : -1, off = (i * 997 + e.seed) % 1;
          const x = ((t * sp * dpr + off * W * 3 + i * 211) % (W + 200 * dpr)) - 100 * dpr, px = dir > 0 ? x : W - x, y = e.y + (dir > 0 ? e.u * 0.5 : 0);
          if (e.tuk) {                                                    // a tuk-tuk: a coloured body, then its tail-light streak
            ctx.fillStyle = ["#2ecc71", "#e84393", "#f1c40f", "#3498db"][i % 4]; ctx.fillRect(px - e.u * 0.6, y - e.u * 0.7, e.u * 1.2, e.u * 0.7);
          }
          const tr = ctx.createLinearGradient(px, y, px - dir * e.u * 6, y); tr.addColorStop(0, "rgba(255,60,60,0.6)"); tr.addColorStop(1, "rgba(255,60,60,0)");
          ctx.fillStyle = tr; ctx.fillRect(Math.min(px, px - dir * e.u * 6), y - e.u * 0.12, e.u * 6, e.u * 0.24);
          ctx.fillStyle = "rgba(255,250,225,0.95)"; ctx.fillRect(px + dir * e.u * 0.6, y - e.u * 0.18, e.u * 0.3, e.u * 0.3);
        }
      } else if (e.kind === "trees") {                                     // the steel trees' canopies, glowing, colours drifting
        for (const [i, tr] of e.trees.entries()) {
          const hue = mode === "rain" ? (t / 60 + i * 50) % 360 : 300 + i * 10;
          ctx.save(); ctx.shadowColor = "hsl(" + hue + ",90%,60%)"; ctx.shadowBlur = e.u * 1.5;
          ctx.fillStyle = "hsla(" + hue + ",85%,55%,0.85)"; ctx.beginPath(); ctx.moveTo(tr.x - tr.w / 2, tr.y); ctx.lineTo(tr.x + tr.w / 2, tr.y);
          ctx.lineTo(tr.x + e.u * 0.3, tr.y + tr.w * 0.6); ctx.lineTo(tr.x - e.u * 0.3, tr.y + tr.w * 0.6); ctx.closePath(); ctx.fill();
          ctx.restore();
        }
      } else if (e.kind === "skybeam") {                                 // the pyramid's sky beam: straight up, shimmering
        const a = 0.22 + (mode === "rain" ? 0.04 * Math.sin(t / 200) : 0), gr = ctx.createLinearGradient(0, e.y, 0, 0);
        gr.addColorStop(0, "rgba(240,248,255," + a + ")"); gr.addColorStop(1, "rgba(240,248,255,0.02)");
        ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(e.x - 3 * dpr, e.y); ctx.lineTo(e.x + 3 * dpr, e.y); ctx.lineTo(e.x + 14 * dpr, 0); ctx.lineTo(e.x - 14 * dpr, 0); ctx.fill();
      } else if (e.kind === "orb") {                                    // the giant ball's display: slow colour fields and a dotted grid
        ctx.save(); ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, Math.PI * 2); ctx.clip();
        const ph = mode === "rain" ? t / 3000 : 1, gr = ctx.createRadialGradient(e.x + Math.cos(ph) * e.r * 0.4, e.y + Math.sin(ph * 0.7) * e.r * 0.3, 0, e.x, e.y, e.r * 1.2);
        gr.addColorStop(0, "hsl(" + ((ph * 40) % 360) + ",95%,62%)"); gr.addColorStop(0.5, "hsl(" + ((ph * 40 + 120) % 360) + ",90%,45%)"); gr.addColorStop(1, "hsl(" + ((ph * 40 + 240) % 360) + ",90%,25%)");
        ctx.fillStyle = gr; ctx.fillRect(e.x - e.r, e.y - e.r, e.r * 2, e.r * 2);
        ctx.fillStyle = "rgba(0,0,0,0.35)"; for (let y = e.y - e.r; y < e.y + e.r; y += 3 * dpr) ctx.fillRect(e.x - e.r, y, e.r * 2, dpr);
        ctx.restore();
      } else if (e.kind === "bike") {                                      // a red bike tearing across, a long light trail behind
        if (mode !== "rain") continue;
        const ph = (t % e.period) / e.period; if (ph > 0.35) continue;
        const x = -W * 0.2 + (W * 1.4) * (ph / 0.35), len = W * 0.35;
        const tr = ctx.createLinearGradient(x - len, 0, x, 0); tr.addColorStop(0, "rgba(255,20,40,0)"); tr.addColorStop(1, "rgba(255,40,60,0.9)");
        ctx.save(); ctx.shadowColor = "#ff2040"; ctx.shadowBlur = e.u * 1.5; ctx.fillStyle = tr; ctx.fillRect(x - len, e.y - e.u * 0.18, len, e.u * 0.36);
        ctx.fillStyle = "#ff2b45"; ctx.fillRect(x - e.u * 1.2, e.y - e.u * 0.7, e.u * 1.6, e.u * 0.7); ctx.restore();
      } else if (e.kind === "lasers") {                                    // the harbour's light show: lasers from the towers
        if (mode !== "rain") continue;
        for (const [i, o] of e.from.entries()) {
          const a = -Math.PI / 2 + Math.sin(t / 1800 + i * 2) * 0.7, len = H * 1.3;
          ctx.strokeStyle = ["rgba(80,255,140,0.35)", "rgba(80,180,255,0.35)", "rgba(220,90,255,0.35)"][i % 3]; ctx.lineWidth = 1.5 * dpr;
          ctx.beginPath(); ctx.moveTo(o.x, o.y); ctx.lineTo(o.x + Math.cos(a) * len, o.y + Math.sin(a) * len); ctx.stroke();
        }
      } else if (e.kind === "bamboolit") {                                      // the bamboo tower lit in the day's colour, edges glowing
        const hue = [0, 30, 55, 120, 200, 260, 300][new Date().getDay()];
        ctx.save(); ctx.globalAlpha = 0.5 + (mode === "rain" ? 0.15 * Math.sin(t / 900) : 0); ctx.strokeStyle = "hsl(" + hue + ",85%,62%)";
        ctx.shadowColor = ctx.strokeStyle; ctx.shadowBlur = e.u; ctx.lineWidth = Math.max(1, e.u * 0.18);
        for (const sgm of e.segs) { ctx.beginPath(); ctx.moveTo(sgm[0], sgm[1]); ctx.lineTo(sgm[2], sgm[3]); ctx.stroke(); }
        ctx.restore();
      } else if (e.kind === "blimp") {                                     // the colonies' advertising blimp drifting over
        const span = W + e.L * 2, x = mode === "rain" ? (((t + e.period * 0.4) % e.period) / e.period) * span - e.L : W * 0.55, y = e.y + Math.sin(t / 3000) * e.u * 0.4;
        const L = e.L, Hh = L * 0.26;
        for (const k of [-0.25, 0.2]) {                                    // searchlights sweeping down from its belly
          const a = Math.PI / 2 + k + Math.sin(t / 1700 + k * 9) * 0.25 * (mode === "rain" ? 1 : 0), len = H;
          const gr = ctx.createLinearGradient(x, y, x + Math.cos(a) * len, y + Math.sin(a) * len);
          gr.addColorStop(0, "rgba(255,245,220,0.18)"); gr.addColorStop(1, "rgba(255,245,220,0)");
          ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(x + k * L * 0.6, y + Hh * 0.4);
          ctx.lineTo(x + Math.cos(a - 0.05) * len, y + Math.sin(a - 0.05) * len); ctx.lineTo(x + Math.cos(a + 0.05) * len, y + Math.sin(a + 0.05) * len); ctx.fill();
        }
        ctx.fillStyle = "#16141f"; ctx.beginPath(); ctx.ellipse(x, y, L / 2, Hh / 2, 0, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = "#0e0c16"; ctx.fillRect(x - L * 0.1, y + Hh * 0.38, L * 0.2, Hh * 0.22);              // the gondola
        const pw = L * 0.62, ph = Hh * 0.42, px = x - pw / 2, py = y - ph / 2;                                 // its LED panel, scrolling
        ctx.fillStyle = "#1c0a06"; ctx.fillRect(px, py, pw, ph);
        ctx.save(); ctx.beginPath(); ctx.rect(px, py, pw, ph); ctx.clip();
        const msg = "OFF-WORLD COLONIES  ·  A NEW LIFE AWAITS  ·  ", fs = ph * 0.62;
        ctx.font = "700 " + fs + "px " + LATIN_FONT; ctx.fillStyle = "#ffb347"; ctx.shadowColor = "#ff8c1a"; ctx.shadowBlur = fs * 0.6; ctx.textBaseline = "middle";
        const tw = ctx.measureText(msg).width, off = mode === "rain" ? (t / 18) % tw : 0;
        for (let k = -1; k < 3; k++) ctx.fillText(msg, px - off + k * tw, py + ph / 2);
        ctx.restore();
        if ((t % 1400) < 140) { ctx.fillStyle = "#ff3355"; ctx.beginPath(); ctx.arc(x - L / 2 + e.u, y, e.u * 0.35, 0, Math.PI * 2); ctx.arc(x + L / 2 - e.u, y, e.u * 0.35, 0, Math.PI * 2); ctx.fill(); }
      } else if (e.kind === "geisha") {
        geishaFace(e, t);
      } else if (e.kind === "shimmer") {                                   // the obelisk's crown: light running up the lattice, fading out at the top
        ctx.save(); ctx.beginPath(); ctx.moveTo(e.x - e.half(e.y + e.h), e.y + e.h);
        for (let y = e.y + e.h; y >= e.y + e.tip; y -= 2) ctx.lineTo(e.x - e.half(y), y);
        ctx.quadraticCurveTo(e.x, e.y - e.tip * 0.6, e.x + e.half(e.y + e.tip), e.y + e.tip);
        for (let y = e.y + e.tip; y <= e.y + e.h; y += 2) ctx.lineTo(e.x + e.half(y), y);
        ctx.closePath(); ctx.clip();
        const hue = mode === "rain" ? 190 + 40 * Math.sin(t / 4000) : 200, ph = mode === "rain" ? (t / 2600) % 1 : 0.5;
        const gr = ctx.createLinearGradient(0, e.y + e.h, 0, e.y - e.tip);
        gr.addColorStop(0, "hsla(" + hue + ",70%,70%,0.55)"); gr.addColorStop(1, "hsla(" + hue + ",70%,80%,0)");
        ctx.fillStyle = gr; ctx.fillRect(e.x - e.half(e.y + e.h), e.y - e.tip, e.half(e.y + e.h) * 2, e.h + e.tip);
        const by = e.y + e.h - ph * (e.h + e.tip), band = ctx.createLinearGradient(0, by - e.h * 0.12, 0, by + e.h * 0.12);
        band.addColorStop(0, "rgba(255,255,255,0)"); band.addColorStop(0.5, "rgba(235,248,255," + (0.45 * (1 - ph)).toFixed(2) + ")"); band.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = band; ctx.fillRect(e.x - e.half(e.y + e.h), by - e.h * 0.12, e.half(e.y + e.h) * 2, e.h * 0.24);
        ctx.restore();
      }
    }
  }
  // Hades: an endless industrial plain glittering to the horizon (seen in the gaps between the towers)
  function hades(g, r) {
    const y0 = horizon - horizon * 0.12;
    g.fillStyle = "#0c0a12"; g.fillRect(0, y0, W, horizon - y0);
    for (let i = 0; i < W * 0.6 / dpr; i++) {
      const y = y0 + Math.pow(r(), 0.7) * (horizon - y0), x = r() * W;
      g.fillStyle = r() < 0.8 ? "rgba(255,180,110," + (0.3 + r() * 0.6).toFixed(2) + ")" : "rgba(160,200,255,0.7)";
      g.fillRect(x, y, dpr * (0.6 + r()), dpr * (0.6 + r()));
    }
  }
  // the geisha billboard (an homage): a stylized face on a giant screen; she blinks, the screen flickers and scans
  function geishaFace(e, t) {
    const { x, y, w, h } = e, cx = x + w / 2;
    const fl = mode === "rain" ? 0.88 + 0.12 * Math.sin(t / 70) * (Math.random() < 0.08 ? 1 : 0.2) : 1;
    ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
    ctx.globalAlpha = fl;
    let gr = ctx.createLinearGradient(0, y, 0, y + h); gr.addColorStop(0, "#2a1338"); gr.addColorStop(1, "#5a1530");
    ctx.fillStyle = gr; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = "#0b0a10";                                            // hair: the bun and the sides
    ctx.beginPath(); ctx.ellipse(cx, y + h * 0.2, w * 0.36, h * 0.16, 0, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.ellipse(cx, y + h * 0.38, w * 0.33, h * 0.24, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "#d9a441";                                            // kanzashi: the hairpins
    ctx.fillRect(cx - w * 0.36, y + h * 0.12, w * 0.24, w * 0.02); ctx.fillRect(cx + w * 0.14, y + h * 0.1, w * 0.22, w * 0.02);
    ctx.beginPath(); ctx.arc(cx + w * 0.3, y + h * 0.13, w * 0.04, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "#f3ece6";                                            // the white-painted face
    ctx.beginPath(); ctx.ellipse(cx, y + h * 0.47, w * 0.22, h * 0.19, 0, 0, Math.PI * 2); ctx.fill();
    const blink = mode === "rain" && (t % 5200) < 160;
    ctx.fillStyle = "#1a0f14";                                            // eyes, with their red wash
    for (const sx of [-1, 1]) {
      ctx.fillStyle = "rgba(200,40,60,0.35)"; ctx.beginPath(); ctx.ellipse(cx + sx * w * 0.09, y + h * 0.44, w * 0.075, h * 0.03, sx * 0.15, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#1a0f14"; ctx.beginPath(); ctx.ellipse(cx + sx * w * 0.09, y + h * 0.445, w * 0.055, blink ? h * 0.003 : h * 0.014, sx * 0.15, 0, Math.PI * 2); ctx.fill();
    }
    ctx.fillStyle = "#c8102e";                                            // lips
    ctx.beginPath(); ctx.ellipse(cx, y + h * 0.56, w * 0.04, h * 0.012, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "#f3ece6"; ctx.beginPath(); ctx.moveTo(cx - w * 0.06, y + h * 0.64); ctx.lineTo(cx + w * 0.06, y + h * 0.64);   // neck and kimono collar
    ctx.lineTo(cx + w * 0.1, y + h * 0.78); ctx.lineTo(cx - w * 0.1, y + h * 0.78); ctx.fill();
    ctx.fillStyle = "#b3123a"; ctx.beginPath(); ctx.moveTo(x, y + h); ctx.lineTo(x, y + h * 0.82); ctx.lineTo(cx - w * 0.04, y + h * 0.74); ctx.lineTo(cx, y + h * 0.86);
    ctx.lineTo(cx + w * 0.04, y + h * 0.74); ctx.lineTo(x + w, y + h * 0.82); ctx.lineTo(x + w, y + h); ctx.fill();
    ctx.fillStyle = "#f0e2c8"; ctx.font = "700 " + Math.round(w * 0.1) + "px " + CJK_FONT; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    [..."強力未来"].forEach((ch, i) => ctx.fillText(ch, x + w * 0.1, y + h * (0.2 + i * 0.12)));
    ctx.globalAlpha = 0.18; ctx.fillStyle = "#000";                       // scanlines
    for (let yy = y; yy < y + h; yy += 3 * dpr) ctx.fillRect(x, yy, w, dpr);
    ctx.restore();
    ctx.save(); ctx.strokeStyle = "rgba(255,120,170,0.5)"; ctx.shadowColor = "#ff5fa0"; ctx.shadowBlur = 18 * dpr; ctx.lineWidth = 2 * dpr; ctx.strokeRect(x, y, w, h); ctx.restore();
  }
  function fogBand(g) {
    const y0 = horizon - horizon * 0.34, y1 = horizon - horizon * 0.05, gr = g.createLinearGradient(0, y0, 0, y1);
    gr.addColorStop(0, "rgba(170,180,215,0)"); gr.addColorStop(0.5, "rgba(170,180,215,0.16)"); gr.addColorStop(1, "rgba(170,180,215,0.05)");
    g.fillStyle = gr; g.fillRect(0, y0, W, y1 - y0);
  }

  function layer(g, r, col, base, minH, maxH, winRate, winAlpha, signRate) {
    const front = signRate > 0.5;
    let x = -10 * dpr;
    while (x < W) {
      const w = (front ? 40 : 28) * dpr + r() * (front ? 110 : 80) * dpr, h = minH + r() * (maxH - minH), top = base - h;
      g.fillStyle = col; g.fillRect(x, top, w, h);
      if (r() < 0.35) g.fillRect(x + w * 0.4, top - h * 0.12, Math.max(2 * dpr, w * 0.06), h * 0.12);    // antenna
      // windows
      const cw = 5 * dpr, ch = 7 * dpr, gx = 4 * dpr, gy = 6 * dpr;
      for (let wy = top + 8 * dpr; wy < base - 10 * dpr; wy += ch + gy)
        for (let wx = x + 6 * dpr; wx < x + w - cw - 4 * dpr; wx += cw + gx)
          if (r() < winRate * 9) {
            g.fillStyle = hexA(r() < 0.75 ? "#e0af68" : r() < 0.5 ? "#7dcfff" : "#f5e0c0", winAlpha * (0.35 + r() * 0.65));
            g.fillRect(wx, wy, cw, ch);
            if (front) wins.push({ x: wx, y: wy, w: cw, h: ch, col });
          }
      if (["seoul", "hk", "bkk", "tp"].includes(scene) && front && r() < 0.55 && w > 60 * dpr) {   // stacked facade signboards, one per floor
        let y = top + h * (0.12 + r() * 0.15);
        for (let k = 0, n = 1 + Math.floor(r() * 3); k < n; k++) {
          const text = HSIGNS[Math.floor(r() * HSIGNS.length)], len = [...text].length;
          const sw = w * (0.7 + r() * 0.2), sh = Math.max(12 * dpr, Math.min(h * 0.09, 26 * dpr)), fs = Math.min(sh * 0.62, sw * 0.82 / len);
          const sx = x + (w - sw) / 2;
          if (y + sh > base - 10 * dpr || fs < 7 * dpr) break;
          if (clear(sx, y, sw, sh)) {
            const light = r() < 0.6;
            signs.push({ text, vertical: false, fs, x: sx, y, w: sw, h: sh, lightbox: light,
                         col: light ? (r() < 0.4 ? "#c8202c" : "#16161e") : NEON[Math.floor(r() * NEON.length)], next: 0, burstEnd: 0, glow: 1 });
          }
          y += sh + (6 + r() * 14) * dpr;
        }
      }
      if (signRate && r() < signRate && w > 30 * dpr) {   // vertical signs hung on the building's edge, sticking out sideways, stacked down it
        const side = r() < 0.5 ? -1 : 1, room = (base - top) - 12 * dpr;
        let fs = Math.round((front ? 13 + r() * 9 : 9 + r() * 4) * dpr), y = top + Math.min(h * 0.08, 14 * dpr) + r() * h * 0.12;
        const count = 1 + Math.floor(r() * (front ? 3 : 2));
        for (let i = 0; i < count; i++) {
          const text = SIGNS[Math.floor(r() * SIGNS.length)], n = [...text].length;
          let f = fs, sh = f * (n * 1.08 + 0.6);
          if (y + sh > top + room) { f = Math.floor((top + room - y) / (n * 1.08 + 0.6)); sh = f * (n * 1.08 + 0.6); }
          if (f < 8 * dpr) break;                                        // no room left above the street
          const sw = f * 1.45, sx = side < 0 ? x - sw * 0.55 : x + w - sw * 0.45;
          if (!clear(sx, y, sw, sh)) { y += sh + (4 + r() * 10) * dpr; continue; }
          signs.push({ text, vertical: true, fs: f, x: sx, y, w: sw, h: sh, side, bx: side < 0 ? x : x + w,
                       col: NEON[Math.floor(r() * NEON.length)], flick: r() < 0.22, dead: r() < 0.18 ? Math.floor(r() * n) : -1,
                       next: 0, burstEnd: 0, glow: front ? 1 : 0.55 });
          y += sh + (4 + r() * 10) * dpr;
        }
      }
      if (signRate && r() < signRate * 0.18 && w > 70 * dpr) {   // a rooftop billboard: a wide glowing panel
        const bw = w * (0.7 + r() * 0.25), bh = bw * (0.28 + r() * 0.12), c1 = NEON[Math.floor(r() * NEON.length)], c2 = NEON[Math.floor(r() * NEON.length)];
        if (clear(x + (w - bw) / 2, top - bh - 6 * dpr, bw, bh)) {
          signs.push({ board: true, x: x + (w - bw) / 2, y: top - bh - 6 * dpr, w: bw, h: bh, col: c1, col2: c2, flick: false, phase: r() * 1000, glow: front ? 0.9 : 0.5 });
          g.fillStyle = col; g.fillRect(x + w * 0.3, top - 6 * dpr, 3 * dpr, 6 * dpr); g.fillRect(x + w * 0.7, top - 6 * dpr, 3 * dpr, 6 * dpr);
        }
      }
      x += w + (front ? 6 : 2) * dpr + r() * 10 * dpr;
    }
  }

  // Tokyo's two towers (the tall one right, the lattice one left), behind the middle buildings: drawn into the city once; their red
  // aircraft beacons blink in frame().
  // Seoul's mountains: two ridges of soft peaks, darker in front
  function ridges(g, r, sets) {
    for (const [col, top, rough] of sets || [["#2a2d58", 0.62, 0.10], ["#1f2247", 0.46, 0.08]]) {
      g.fillStyle = col; g.beginPath(); g.moveTo(0, horizon);
      let x = 0, y = horizon - (horizon * top) * (0.5 + r() * 0.5);
      g.lineTo(0, y);
      while (x < W) {
        const nx = x + W * (0.05 + r() * 0.09), ny = horizon - horizon * top * (0.35 + r() * 0.65) + (r() - 0.5) * horizon * rough;
        g.quadraticCurveTo((x + nx) / 2, Math.min(y, ny) - horizon * rough * r(), nx, ny); x = nx; y = ny;
      }
      g.lineTo(W, horizon); g.closePath(); g.fill();
    }
  }

  function landmarks(g, which) {
    const u0 = Math.min(W, H * 1.2) / 100;
    // glass: a vertical gradient tower body with scattered lit floors (most of the new landmarks start from this)
    const glass = (x0, x1, y0, c0, c1) => { const gr = g.createLinearGradient(x0, 0, x1, 0); gr.addColorStop(0, c0); gr.addColorStop(0.5, c1); gr.addColorStop(1, c0); return gr; };
    const floors = (cx, hw, y0, y1, k, a) => { g.fillStyle = "rgba(255,226,170," + (a || 0.45) + ")"; for (let y = y0; y < y1; y += u0 * 0.9) if (Math.sin(y * (k || 17.3)) > 0.5) g.fillRect(cx - hw, y, hw * 2, u0 * 0.16); };
    if (which === "fins") {
    // ---- a tall pale tower stepping in at the top to a crown of fins
    const x = W * (W > H ? 0.32 : 0.3), top = horizon - Math.min(horizon * 0.78, H * 0.58), b = u0 * 2.6;
    g.fillStyle = glass(x - b, x + b, top, "#2a3550", "#6e7fa8"); g.fillRect(x - b, top + u0 * 6, b * 2, horizon - top - u0 * 6);
    g.fillRect(x - b * 0.8, top + u0 * 3, b * 1.6, u0 * 3.2);
    g.save(); g.shadowColor = "#e8f0ff"; g.shadowBlur = u0; g.fillStyle = "#dfe7ff";
    for (let k = -2; k <= 2; k++) { g.beginPath(); g.moveTo(x + k * b * 0.32 - u0 * 0.25, top + u0 * 3); g.lineTo(x + k * b * 0.32, top + (Math.abs(k) * u0)); g.lineTo(x + k * b * 0.32 + u0 * 0.25, top + u0 * 3); g.fill(); }
    g.restore(); floors(x, b * 0.85, top + u0 * 7, horizon - u0);
    extras.push({ kind: "lasers", from: [{ x, y: top }] });
    return;
    }
    if (which === "prism") {
    // ---- a prism of triangles, its white X-framing lit, two masts
    const x = W * (W > H ? 0.58 : 0.62), top = horizon - Math.min(horizon * 0.66, H * 0.5), b = u0 * 2.8, hh = horizon - top;
    g.fillStyle = glass(x - b, x + b, top, "#1a2640", "#3c5a8a"); g.beginPath(); g.moveTo(x - b, horizon); g.lineTo(x - b, top + hh * 0.25); g.lineTo(x, top); g.lineTo(x + b * 0.2, top + hh * 0.08); g.lineTo(x + b, top + hh * 0.5); g.lineTo(x + b, horizon); g.closePath(); g.fill();
    g.save(); g.strokeStyle = "rgba(235,242,255,0.85)"; g.shadowColor = "#e8f0ff"; g.shadowBlur = u0 * 0.6; g.lineWidth = Math.max(1, u0 * 0.18);
    for (let y = horizon; y > top + hh * 0.3; y -= hh * 0.18) { g.beginPath(); g.moveTo(x - b, y); g.lineTo(x + b, y - hh * 0.18); g.moveTo(x + b, y); g.lineTo(x - b, y - hh * 0.18); g.stroke(); }
    g.restore(); g.fillStyle = "#cfd8ff"; g.fillRect(x - u0 * 0.1, top - u0 * 5, u0 * 0.2, u0 * 5); g.fillRect(x + b * 0.2 - u0 * 0.1, top + hh * 0.08 - u0 * 4, u0 * 0.2, u0 * 4);
    beacons.push({ x, y: top - u0 * 5, r: u0 * 0.3 });
    const l = extras.find((e) => e.kind === "lasers"); if (l) l.from.push({ x, y: top }, { x: x + b * 0.2, y: top + hh * 0.08 });
    return;
    }
    if (which === "spheres") {
    // ---- the TV tower: three slanted legs, the shaft, a big and a small pink sphere, the spire
    const x = W * (W > H ? 0.28 : 0.24), base = horizon, top = horizon - Math.min(horizon * 0.82, H * 0.6), hh = base - top;
    const s1 = base - hh * 0.3, s2 = base - hh * 0.62, r1 = u0 * 3.2, r2 = u0 * 2;
    g.strokeStyle = "#5a5f88"; g.lineWidth = u0 * 0.7;
    for (const k of [-1, 1]) { g.beginPath(); g.moveTo(x + k * u0 * 4, base); g.lineTo(x + k * u0 * 0.8, s1 - r1 * 0.5); g.stroke(); }
    g.fillStyle = "#6a6f9a"; g.fillRect(x - u0 * 0.7, s2, u0 * 1.4, base - s2); g.fillRect(x - u0 * 0.35, top + u0 * 4, u0 * 0.7, s2 - top - u0 * 4);
    g.fillStyle = "#e9e6ff"; g.fillRect(x - u0 * 0.12, top, u0 * 0.24, u0 * 4.5);
    g.save(); g.shadowColor = "#ff5fa8"; g.shadowBlur = u0 * 2.2;
    for (const [cy, rr] of [[s1, r1], [s2, r2], [top + u0 * 5, u0 * 0.9]]) {
      const gr = g.createRadialGradient(x - rr * 0.3, cy - rr * 0.3, rr * 0.1, x, cy, rr); gr.addColorStop(0, "#ffd1e8"); gr.addColorStop(0.6, "#ff4fa0"); gr.addColorStop(1, "#8a1d5e");
      g.fillStyle = gr; g.beginPath(); g.arc(x, cy, rr, 0, Math.PI * 2); g.fill();
    }
    g.restore(); beacons.push({ x, y: top, r: u0 * 0.3 });
    return;
    }
    if (which === "pagoda") {
    // ---- a pagoda's stepped tiers narrowing to a spire, lit gold
    const x = W * (W > H ? 0.54 : 0.5), top = horizon - Math.min(horizon * 0.66, H * 0.5), b = u0 * 2.4, hh = horizon - top;
    g.fillStyle = glass(x - b, x + b, top, "#2c2a3e", "#5b5470");
    let y = horizon, w = b;
    for (let i = 0; i < 9; i++) { const h = hh * 0.11 * (1 - i * 0.05); g.fillRect(x - w, y - h, w * 2, h); g.save(); g.fillStyle = "rgba(255,210,120,0.6)"; g.fillRect(x - w * 1.05, y - h, w * 2.1, u0 * 0.18); g.restore(); y -= h; w *= 0.88; }
    g.save(); g.shadowColor = "#ffd27a"; g.shadowBlur = u0; g.fillStyle = "#ffe0a0"; g.beginPath(); g.moveTo(x - w, y); g.lineTo(x, top); g.lineTo(x + w, y); g.fill(); g.restore();
    return;
    }
    if (which === "opener") {
    // ---- a tapering slab with the trapezoid opening at the top ("the bottle opener")
    const x = W * (W > H ? 0.61 : 0.6), top = horizon - Math.min(horizon * 0.76, H * 0.57), b = u0 * 3, t2 = u0 * 1.6, hh = horizon - top;
    g.fillStyle = glass(x - b, x + b, top, "#1c2440", "#47608f"); g.beginPath(); g.moveTo(x - b, horizon); g.lineTo(x - t2, top); g.lineTo(x + t2, top); g.lineTo(x + b, horizon); g.closePath(); g.fill();
    g.globalCompositeOperation = "destination-out"; g.beginPath(); g.moveTo(x - t2 * 0.7, top + u0 * 0.8); g.lineTo(x + t2 * 0.7, top + u0 * 0.8); g.lineTo(x + t2 * 0.9, top + u0 * 3.2); g.lineTo(x - t2 * 0.9, top + u0 * 3.2); g.closePath(); g.fill();
    g.globalCompositeOperation = "source-over"; floors(x, b * 0.7, top + u0 * 5, horizon - u0, 13.7);
    return;
    }
    if (which === "twist") {
    // ---- the tallest, a softly twisting taper, its spiral notch traced in light
    const x = W * (W > H ? 0.7 : 0.76), top = horizon - Math.min(horizon * 0.9, H * 0.66), b = u0 * 3.2, tip = u0 * 1.2, hh = horizon - top;
    const half = (y) => tip + (b - tip) * Math.pow((y - top) / hh, 0.7);
    g.fillStyle = glass(x - b, x + b, top, "#1c2a48", "#5a7fb0"); g.beginPath(); g.moveTo(x - b, horizon);
    for (let y = horizon; y >= top; y -= u0 * 0.5) g.lineTo(x - half(y), y);
    g.lineTo(x + tip * 0.6, top - u0 * 0.6);
    for (let y = top; y <= horizon; y += u0 * 0.5) g.lineTo(x + half(y), y); g.closePath(); g.fill();
    g.save(); g.strokeStyle = "rgba(200,225,255,0.55)"; g.lineWidth = Math.max(1, u0 * 0.14); g.beginPath();
    for (let y = horizon; y >= top; y -= u0 * 0.5) { const k = (horizon - y) / hh; g.lineTo(x + half(y) * Math.cos(k * Math.PI * 2.2), y); }
    g.stroke(); g.restore(); floors(x, b * 0.6, top + hh * 0.1, horizon - u0, 19.1, 0.35);
    beacons.push({ x: x + tip * 0.6, y: top - u0 * 0.6, r: u0 * 0.3 });
    return;
    }
    if (which === "bamboo") {
    // ---- eight flared tiers stacked like bamboo on a tapered base, a pinnacle; its edges lit in the day's colour
    const x = W * (W > H ? 0.6 : 0.62), top = horizon - Math.min(horizon * 0.86, H * 0.64), hh = horizon - top, b = u0 * 2.6;
    const baseH = hh * 0.22, tierH = (hh - baseH - hh * 0.16) / 8, segs = [];
    g.fillStyle = glass(x - b, x + b, top, "#1c3a3a", "#4d8a84");
    g.beginPath(); g.moveTo(x - b * 1.25, horizon); g.lineTo(x - b * 0.9, horizon - baseH); g.lineTo(x + b * 0.9, horizon - baseH); g.lineTo(x + b * 1.25, horizon); g.fill();
    let y = horizon - baseH;
    for (let i = 0; i < 8; i++) {
      g.beginPath(); g.moveTo(x - b * 0.8, y); g.lineTo(x - b, y - tierH); g.lineTo(x + b, y - tierH); g.lineTo(x + b * 0.8, y); g.fill();
      segs.push([x - b * 0.8, y, x - b, y - tierH], [x + b * 0.8, y, x + b, y - tierH]);
      y -= tierH;
    }
    g.fillRect(x - b * 0.5, y - hh * 0.05, b, hh * 0.05); g.fillStyle = "#d9f3ee"; g.fillRect(x - u0 * 0.15, top, u0 * 0.3, y - hh * 0.05 - top);
    floors(x, b * 0.75, horizon - baseH - tierH * 8, horizon - u0, 23.3, 0.35);
    extras.push({ kind: "bamboolit", segs, u: u0 });
    beacons.push({ x, y: top, r: u0 * 0.3 });
    return;
    }
    if (which === "skypark") {
    // ---- three towers leaning together, the long skypark "ship" across their tops
    const x = W * (W > H ? 0.6 : 0.58), top = horizon - Math.min(horizon * 0.5, H * 0.38), b = u0 * 1.6, gap = u0 * 5.2;
    for (const k of [-1, 0, 1]) {
      const cx = x + k * gap;
      g.fillStyle = glass(cx - b * 1.2, cx + b, top, "#262c46", "#5c6a96"); g.beginPath(); g.moveTo(cx - b * 1.4, horizon); g.lineTo(cx - b * 0.6, top); g.lineTo(cx + b, top); g.lineTo(cx + b, horizon); g.fill();
      floors(cx, b * 0.9, top + u0 * 2, horizon - u0, 31.1 + k, 0.5);
    }
    g.save(); g.shadowColor = "#d7f0ff"; g.shadowBlur = u0; g.fillStyle = "#c8d6ea";
    g.beginPath(); g.moveTo(x - gap - b * 1.6, top - u0 * 0.3); g.lineTo(x + gap + b * 4.5, top - u0 * 0.6); g.lineTo(x + gap + b * 4.8, top - u0 * 1.6); g.lineTo(x - gap - b * 1.2, top - u0 * 1.4); g.closePath(); g.fill();
    g.restore();
    return;
    }
    if (which === "pyramid") {
    // ---- a black glass pyramid with lit edges (its beam is drawn per frame)
    const x = W * (W > H ? 0.2 : 0.18), top = horizon - Math.min(horizon * 0.32, H * 0.24), b = (horizon - top) * 0.95;
    g.fillStyle = "#0b0a14"; g.beginPath(); g.moveTo(x - b, horizon); g.lineTo(x, top); g.lineTo(x + b, horizon); g.fill();
    g.save(); g.strokeStyle = "rgba(255,240,200,0.55)"; g.lineWidth = Math.max(1, u0 * 0.15); g.shadowColor = "#fff0c8"; g.shadowBlur = u0 * 0.6;
    g.beginPath(); g.moveTo(x - b, horizon); g.lineTo(x, top); g.lineTo(x + b, horizon); g.stroke(); g.restore();
    return;
    }
    if (which === "needle") {
    // ---- a slim shaft rising to a stacked pod and a needle
    const x = W * (W > H ? 0.84 : 0.86), top = horizon - Math.min(horizon * 0.84, H * 0.62), hh = horizon - top, pod = top + hh * 0.12;
    g.fillStyle = "#3a3550"; g.beginPath(); g.moveTo(x - u0 * 1.4, horizon); g.lineTo(x - u0 * 0.6, pod); g.lineTo(x + u0 * 0.6, pod); g.lineTo(x + u0 * 1.4, horizon); g.fill();
    g.save(); g.shadowColor = "#ffd27a"; g.shadowBlur = u0;
    for (let i = 0; i < 4; i++) { g.fillStyle = i % 2 ? "#ffe2a8" : "#c9b4ff"; g.fillRect(x - u0 * (2 - i * 0.2), pod + i * u0 * 0.7, u0 * (4 - i * 0.4), u0 * 0.6); }
    g.restore(); g.fillStyle = "#e8e4ff"; g.fillRect(x - u0 * 0.12, top, u0 * 0.24, pod - top);
    beacons.push({ x, y: top, r: u0 * 0.3 });
    return;
    }
    if (which === "orb") {
    // ---- a giant ball of LEDs rising from among the hotels (its display is drawn per frame)
    const rr = Math.min(W, H) * (W > H ? 0.11 : 0.16), x = W * 0.5, y = horizon - rr * 0.75;
    extras.push({ kind: "orb", x, y, r: rr });
    signs.push({ block: true, x: x - rr, y: y - rr, w: rr * 2, h: rr * 2 });
    return;
    }
    if (which === "rings") {
    // ---- a tall slab whose crown rings are lit in rainbow bands
    const x = W * (W > H ? 0.3 : 0.26), top = horizon - Math.min(horizon * 0.7, H * 0.52), b = u0 * 2.4;
    g.fillStyle = glass(x - b, x + b, top, "#262640", "#545487"); g.fillRect(x - b, top + u0 * 3, b * 2, horizon - top - u0 * 3);
    g.save(); g.shadowBlur = u0;
    ["#ff4d6d", "#ffb347", "#f9f871", "#6bffb8", "#57c7ff", "#b388ff"].forEach((c, i) => { g.shadowColor = c; g.fillStyle = c; g.fillRect(x - b * 1.05, top + u0 * 3 + i * u0 * 0.7, b * 2.1, u0 * 0.4); });
    g.restore(); g.fillStyle = "#e0dcff"; g.fillRect(x - u0 * 0.12, top - u0 * 3, u0 * 0.24, u0 * 6);
    floors(x, b * 0.85, top + u0 * 8, horizon - u0, 9.9); beacons.push({ x, y: top - u0 * 3, r: u0 * 0.3 });
    return;
    }
    if (which === "pixels") {
    // ---- a slim glass tower with its pixel spiral, blocks cut away round the facade
    const x = W * (W > H ? 0.64 : 0.68), top = horizon - Math.min(horizon * 0.82, H * 0.62), b = u0 * 2.2, hh = horizon - top;
    g.fillStyle = glass(x - b, x + b, top, "#1e2a44", "#5e7aa8"); g.fillRect(x - b, top, b * 2, hh);
    g.globalCompositeOperation = "destination-out";
    for (let y = top; y < horizon - u0; y += u0 * 1.1) {
      const k = (y - top) / hh, px = x - b + ((Math.sin(k * Math.PI * 3) + 1) / 2) * b * 1.4;
      g.fillRect(px, y, b * 0.6, u0 * 1.1);
    }
    g.globalCompositeOperation = "source-over"; floors(x, b * 0.8, top + u0, horizon - u0, 27.7, 0.4);
    return;
    }
    if (which === "neotower") {
    // ---- Neo-Tokyo's towers: two vast slabs striped with vertical light, rising out of the rebuilt city
    for (const [x, k] of [[W * 0.36, 0.86], [W * 0.62, 1]]) {
      const top = horizon - Math.min(horizon * 0.8, H * 0.6) * k, b = u0 * 4 * k;
      g.fillStyle = glass(x - b, x + b, top, "#140d16", "#3a2433"); g.fillRect(x - b, top, b * 2, horizon - top);
      g.save(); g.shadowColor = "#ff4060"; g.shadowBlur = u0 * 0.6;
      for (let i = -2; i <= 2; i++) { g.fillStyle = i ? "rgba(255,80,100,0.5)" : "rgba(255,210,200,0.75)"; g.fillRect(x + i * b * 0.4 - u0 * 0.08, top + u0, u0 * 0.16, horizon - top - u0 * 2); }
      g.restore(); g.fillStyle = "#ffdcdc"; g.fillRect(x - b, top, b * 2, u0 * 0.4);
      beacons.push({ x: x - b * 0.8, y: top - u0 * 0.3, r: u0 * 0.3 }, { x: x + b * 0.8, y: top - u0 * 0.3, r: u0 * 0.3 });
    }
    return;
    }
    if (which === "arcology") {
    // ---- the two vast pyramids: vast stepped slopes glittering with windows, searchlights at the top
    for (const [px, k] of [[W * (W > H ? 0.22 : 0.18), 0.7], [W * (W > H ? 0.4 : 0.42), 1]]) {
      const ph = Math.min(horizon * 0.64, H * 0.5) * k, pb = (W > H ? W * 0.2 : W * 0.36) * k, pt = horizon - ph;
      g.fillStyle = "#1a1420"; g.beginPath(); g.moveTo(px - pb, horizon); g.lineTo(px - pb * 0.12, pt); g.lineTo(px + pb * 0.12, pt); g.lineTo(px + pb, horizon); g.closePath(); g.fill();
      for (let y = pt + u0 * 0.4; y < horizon; y += u0 * 0.55) {         // the glittering terraces
        const hw = pb * 0.12 + (pb - pb * 0.12) * (y - pt) / ph;
        for (let x = px - hw; x < px + hw; x += u0 * 0.5) if (Math.sin(x * 12.98 + y * 78.23) > 0.35) {
          g.fillStyle = Math.sin(x * 3.1 + y) > 0.7 ? "rgba(255,210,150,0.85)" : "rgba(255,170,90,0.45)"; g.fillRect(x, y, u0 * 0.22, u0 * 0.16);
        }
      }
      g.fillStyle = "rgba(255,200,140,0.25)"; g.fillRect(px - pb * 0.12, pt - u0 * 0.6, pb * 0.24, u0 * 0.6);
      if (k === 1) for (let i = 0; i < 3; i++) extras.push({ kind: "beam", x: px + (i - 1) * pb * 0.08, y: pt, a0: -Math.PI / 2 + (i - 1) * 0.5, p: 3000 + i * 1300, ph: i * 2 });
    }
    return;
    }
    if (which === "geisha") {
    // ---- the tower carrying the giant screen (the face itself is drawn every frame)
    const gx = W * (W > H ? 0.74 : 0.7), tw = Math.max(u0 * 5, W * (W > H ? 0.05 : 0.12)), tt = horizon - Math.min(horizon * 0.5, H * 0.38);
    g.fillStyle = "#0d0b16"; g.fillRect(gx - tw / 2, tt, tw, horizon - tt);
    g.fillStyle = "rgba(255,200,140,0.35)";
    for (let y = tt + u0; y < horizon; y += u0 * 0.8) if (Math.sin(y * 7.7) > 0.6) g.fillRect(gx - tw / 2 + u0 * 0.3, y, tw - u0 * 0.6, u0 * 0.12);
    const sw = tw * 0.86, sh = sw * 1.5;
    extras.push({ kind: "geisha", x: gx - sw / 2, y: tt + u0 * 3, w: sw, h: sh });
    signs.push({ block: true, x: gx - sw / 2, y: tt + u0 * 3, w: sw, h: sh });   // keeps the signs off her screen (never drawn)
    beacons.push({ x: gx, y: tt - u0 * 0.3, r: u0 * 0.35 });
    return;
    }
    if (which === "mast") {
    // ---- the TV mast on the hill: three splayed legs, two crossbars, red lights
    const sx = W * (W > H ? 0.14 : 0.12), hill = horizon - Math.min(horizon * 0.42, H * 0.3), hw = W * 0.14;
    g.fillStyle = "#1a1d3d"; g.beginPath(); g.moveTo(sx - hw, horizon);
    g.bezierCurveTo(sx - hw * 0.4, horizon - (horizon - hill) / 0.75, sx + hw * 0.4, horizon - (horizon - hill) / 0.75, sx + hw, horizon); g.closePath(); g.fill();
    const tt = hill - Math.min(horizon * 0.28, H * 0.2), legs = [-1.6, 0, 1.6];
    g.strokeStyle = "#4a3f6e"; g.lineWidth = Math.max(1, u0 * 0.3);
    for (const l of legs) { g.beginPath(); g.moveTo(sx + l * u0 * 1.6, hill + u0); g.lineTo(sx + l * u0 * 0.5, tt); g.stroke(); }
    for (const k of [0.35, 0.72]) { const y = hill - (hill - tt) * k; g.beginPath(); g.moveTo(sx - u0 * 1.6 * (1 - k * 0.7), y); g.lineTo(sx + u0 * 1.6 * (1 - k * 0.7), y); g.stroke(); }
    for (const l of legs) { g.beginPath(); g.moveTo(sx + l * u0 * 0.5, tt); g.lineTo(sx + l * u0 * 0.5, tt - u0 * 3.5); g.stroke(); }
    beacons.push({ x: sx - u0 * 0.8, y: tt - u0 * 3.6, r: u0 * 0.3 }, { x: sx, y: tt - u0 * 3.6, r: u0 * 0.3 }, { x: sx + u0 * 0.8, y: tt - u0 * 3.6, r: u0 * 0.3 },
                 { x: sx, y: hill - (hill - tt) * 0.72, r: u0 * 0.25 });
    return;
    }
    if (which === "spike") {
    // ---- a white floodlit spike with its two wings near the top
    const px = W * (W > H ? 0.46 : 0.42), pt = horizon - Math.min(horizon * 0.62, H * 0.46), b = u0 * 2.8;
    g.save(); g.shadowColor = "#e8e9ff"; g.shadowBlur = u0 * 1.2;
    const gr = g.createLinearGradient(0, pt, 0, horizon); gr.addColorStop(0, "#f2f2ff"); gr.addColorStop(0.5, "#b9bcd8"); gr.addColorStop(1, "#5d6185");
    g.fillStyle = gr; g.beginPath(); g.moveTo(px - b, horizon); g.lineTo(px, pt); g.lineTo(px + b, horizon); g.closePath(); g.fill();
    const wy = pt + (horizon - pt) * 0.22, wh = (horizon - pt) * 0.14, ww = b * 0.22 * 1.6;
    g.fillRect(px - b * 0.22 - ww * 0.7, wy, ww, wh); g.fillRect(px + b * 0.22 - ww * 0.3, wy, ww, wh);   // the wings
    g.shadowBlur = 0; g.fillStyle = "rgba(60,64,100,0.35)";
    for (let y = pt + (horizon - pt) * 0.3; y < horizon; y += u0 * 0.7) { const hw = b * (y - pt) / (horizon - pt); g.fillRect(px - hw * 0.9, y, hw * 1.8, u0 * 0.12); }
    g.restore();
    beacons.push({ x: px, y: pt - u0 * 0.2, r: u0 * 0.35 });
    return;
    }
    if (which === "obelisk") {
    // ---- a slim obelisk tapering to a narrow rounded top; its upper crown is an open lattice of light,
    // so the glass fades out into the sky (the shimmer that runs up it is drawn per frame)
    const fx = W * (W > H ? 0.68 : 0.72), ft = horizon - Math.min(horizon * 0.8, H * 0.6), fh = horizon - ft, b = u0 * 2.6, tip = b * 0.36;
    const half = (y) => tip + (b - tip) * Math.pow((y - ft) / fh, 0.55);
    const shape = () => { g.beginPath(); g.moveTo(fx - b, horizon);
      for (let y = horizon; y >= ft + tip; y -= u0 * 0.5) g.lineTo(fx - half(y), y);
      g.quadraticCurveTo(fx, ft - tip * 0.6, fx + half(ft + tip), ft + tip);
      for (let y = ft + tip; y <= horizon; y += u0 * 0.5) g.lineTo(fx + half(y), y); g.closePath(); };
    g.save();
    const gr = g.createLinearGradient(0, ft, 0, horizon);                 // glass, fading out over the top sixth
    gr.addColorStop(0, "rgba(60,80,140,0)"); gr.addColorStop(0.16, "rgba(55,72,128,0.55)"); gr.addColorStop(0.24, "#2a3769"); gr.addColorStop(1, "#151a38");
    g.fillStyle = gr; shape(); g.fill();
    shape(); g.clip();
    g.strokeStyle = "rgba(170,190,255,0.14)"; g.lineWidth = Math.max(1, u0 * 0.1);                  // the vertical fins
    for (let k = -3; k <= 3; k++) { g.beginPath(); g.moveTo(fx + k * b * 0.27, horizon); g.lineTo(fx + k * tip * 0.27, ft); g.stroke(); }
    g.fillStyle = "rgba(255,226,170,0.45)";
    for (let y = ft + fh * 0.26; y < horizon - u0; y += u0 * 0.9) if (Math.sin(y * 21.7) > 0.6) g.fillRect(fx - half(y) * 0.8, y, half(y) * 1.6, u0 * 0.18);
    g.restore();
    extras.push({ kind: "shimmer", x: fx, y: ft, h: fh * 0.24, half, tip });
    beacons.push({ x: fx, y: ft - tip * 0.3, r: u0 * 0.3 });
    return;
    }
    if (which === "sail") {
    // ---- a glass tower with a sloped sail top, an LED strip up its edge, a spire
    const wx = W * (W > H ? 0.66 : 0.7), wt = horizon - Math.min(horizon * 0.74, H * 0.56), b = u0 * 3.2;
    g.save();
    const gr = g.createLinearGradient(wx - b, 0, wx + b, 0); gr.addColorStop(0, "#161b3e"); gr.addColorStop(0.6, "#2f3c74"); gr.addColorStop(1, "#141832");
    g.fillStyle = gr; g.beginPath(); g.moveTo(wx - b, horizon); g.lineTo(wx - b, wt + u0 * 6); g.lineTo(wx + b * 0.6, wt); g.lineTo(wx + b, wt + u0 * 2); g.lineTo(wx + b, horizon); g.closePath(); g.fill();
    g.shadowColor = "#7dcfff"; g.shadowBlur = u0; g.strokeStyle = "#9fd8ff"; g.lineWidth = Math.max(1, u0 * 0.22);
    g.beginPath(); g.moveTo(wx - b, wt + u0 * 6); g.lineTo(wx + b * 0.6, wt); g.stroke();                       // the sail's lit edge
    g.shadowBlur = 0; g.fillStyle = "#cfe8ff"; g.fillRect(wx + b * 0.6 - u0 * 0.12, wt - u0 * 7, u0 * 0.24, u0 * 7);   // the spire
    g.fillStyle = "rgba(255,226,170,0.45)";
    for (let y = wt + u0 * 8; y < horizon - u0; y += u0 * 0.9) if (Math.sin(y * 17.3) > 0.55) g.fillRect(wx - b * 0.85, y, b * 1.7, u0 * 0.18);
    g.restore();
    beacons.push({ x: wx + b * 0.6, y: wt - u0 * 7, r: u0 * 0.35 });
    return;
    }
    if (which === "crown") {
    // ---- a round tower stepping in near the top, crowned with a lit glass ring
    const bx = W * (W > H ? 0.42 : 0.36), bt = horizon - Math.min(horizon * 0.66, H * 0.5), b = u0 * 3;
    g.save();
    const gr = g.createLinearGradient(bx - b, 0, bx + b, 0); gr.addColorStop(0, "#14183a"); gr.addColorStop(0.5, "#3a3f6e"); gr.addColorStop(1, "#13162f");
    g.fillStyle = gr;
    g.fillRect(bx - b, bt + u0 * 6, b * 2, horizon - bt - u0 * 6); g.fillRect(bx - b * 0.85, bt + u0 * 3, b * 1.7, u0 * 3.2); g.fillRect(bx - b * 0.7, bt + u0 * 1.5, b * 1.4, u0 * 1.6);
    g.shadowColor = "#e8f4ff"; g.shadowBlur = u0 * 1.6; g.fillStyle = "rgba(225,240,255,0.9)";
    g.beginPath(); g.ellipse(bx, bt + u0 * 1.5, b * 0.7, u0 * 1.4, 0, Math.PI, 0); g.fill();                     // the glass crown
    g.shadowBlur = 0; g.fillStyle = "rgba(255,226,170,0.45)";
    for (let y = bt + u0 * 7; y < horizon - u0; y += u0 * 0.9) if (Math.sin(y * 13.1) > 0.5) g.fillRect(bx - b * 0.85, y, b * 1.7, u0 * 0.18);
    g.restore();
    return;
    }
    if (which === "tubes") {
    // ---- black bundled tubes stepping back, two white antennas
    const vx = W * (W > H ? 0.62 : 0.64), vt = horizon - Math.min(horizon * 0.66, H * 0.5), c = u0 * 1.5, hh = horizon - vt;
    const cols = [[-1, 0.62], [0, 1], [1, 0.84], [-0.5, 0.9], [0.5, 0.72]];
    g.save(); g.fillStyle = "#0b0c19";
    for (const [k, f] of cols) g.fillRect(vx + k * c * 1.6 - c, horizon - hh * f, c * 2, hh * f);
    g.fillStyle = "rgba(255,226,170,0.35)";
    for (let y = vt + u0 * 2; y < horizon - u0; y += u0 * 0.9) if (Math.sin(y * 9.7) > 0.5) g.fillRect(vx - c * 2.4, y, c * 4.8, u0 * 0.14);
    g.fillStyle = "#dfe3ff"; g.fillRect(vx - c * 0.6, vt - u0 * 7, u0 * 0.22, u0 * 7); g.fillRect(vx + c * 0.6, vt - u0 * 7.6, u0 * 0.22, u0 * 7.6);
    g.restore();
    beacons.push({ x: vx - c * 0.6, y: vt - u0 * 7, r: u0 * 0.3 }, { x: vx + c * 0.6, y: vt - u0 * 7.6, r: u0 * 0.3 });
    return;
    }
    if (which === "braced") {
    // ---- a tapered black tower with its X-bracing, a lit crown band, twin antennas
    const hx = W * (W > H ? 0.3 : 0.28), ht = horizon - Math.min(horizon * 0.58, H * 0.44), b0 = u0 * 3.4, b1 = u0 * 2.1;
    g.save(); g.fillStyle = "#1c1e33"; g.beginPath(); g.moveTo(hx - b0, horizon); g.lineTo(hx - b1, ht); g.lineTo(hx + b1, ht); g.lineTo(hx + b0, horizon); g.closePath(); g.fill();
    g.fillStyle = "rgba(255,226,170,0.4)";                                // its lit floors between the braces
    for (let y = ht + u0; y < horizon - u0; y += u0 * 0.7) if (Math.sin(y * 11.3) > 0.4) { const w = b1 + (b0 - b1) * (y - ht) / (horizon - ht); g.fillRect(hx - w * 0.85, y, w * 1.7, u0 * 0.14); }
    g.shadowColor = "#cfd8ff"; g.shadowBlur = u0 * 0.6;
    g.strokeStyle = "rgba(215,222,255,0.8)"; g.lineWidth = Math.max(1, u0 * 0.22);   // the X-bracing, its signature
    const seg = (horizon - ht) / 5, wAt = (y) => b1 + (b0 - b1) * (y - ht) / (horizon - ht);
    for (let i = 0; i < 5; i++) { const y0 = ht + seg * i, y1 = y0 + seg; g.beginPath(); g.moveTo(hx - wAt(y0), y0); g.lineTo(hx + wAt(y1), y1); g.moveTo(hx + wAt(y0), y0); g.lineTo(hx - wAt(y1), y1); g.stroke(); }
    g.shadowBlur = u0 * 1.4; g.fillStyle = "rgba(255,255,255,0.95)"; g.fillRect(hx - b1, ht, b1 * 2, u0 * 1.1); g.shadowBlur = 0;   // its white crown band
    g.fillStyle = "#dfe3ff"; g.fillRect(hx - b1 * 0.5, ht - u0 * 6, u0 * 0.22, u0 * 6); g.fillRect(hx + b1 * 0.5, ht - u0 * 6, u0 * 0.22, u0 * 6);
    g.restore();
    beacons.push({ x: hx - b1 * 0.5, y: ht - u0 * 6, r: u0 * 0.3 }, { x: hx + b1 * 0.5, y: ht - u0 * 6, r: u0 * 0.3 });
    return;
    }
    if (which === "frustums") {
    // ---- three stacked frustums of teal glass, wider and narrower in turn
    const sx = W * (W > H ? 0.82 : 0.86), st = horizon - Math.min(horizon * 0.56, H * 0.42), sh = horizon - st, b = u0 * 2.4;
    g.save();
    const gr = g.createLinearGradient(sx - b, 0, sx + b, 0); gr.addColorStop(0, "#123a46"); gr.addColorStop(0.5, "#2c7f8c"); gr.addColorStop(1, "#0f3038");
    g.fillStyle = gr; g.beginPath(); g.moveTo(sx - b, horizon);
    for (let y = horizon; y >= st; y -= u0 * 0.4) g.lineTo(sx - b * (0.78 + 0.22 * Math.cos(((horizon - y) / sh) * Math.PI * 3)), y);
    for (let y = st; y <= horizon; y += u0 * 0.4) g.lineTo(sx + b * (0.78 + 0.22 * Math.cos(((horizon - y) / sh) * Math.PI * 3)), y);
    g.closePath(); g.fill();
    g.fillStyle = "rgba(200,245,255,0.35)"; for (let y = st + u0; y < horizon; y += u0 * 0.8) if (Math.sin(y * 5.3) > 0.3) g.fillRect(sx - b * 0.6, y, b * 1.2, u0 * 0.12);
    g.restore();
    return;
    }
    if (which === "cobs") {
    // ---- the two corncobs, scalloped balconies with their lights
    const mx = W * (W > H ? 0.48 : 0.5), mt = horizon - Math.min(horizon * 0.34, H * 0.25), rr = u0 * 1.7;
    g.save();
    for (const cx of [mx - rr * 1.4, mx + rr * 1.4]) {
      g.fillStyle = "#1a1c33"; g.fillRect(cx - rr, mt, rr * 2, horizon - mt);
      for (let y = mt + u0 * 0.3; y < horizon - u0 * 4; y += u0 * 0.55) {
        g.fillStyle = "rgba(205,210,235,0.55)"; g.beginPath(); g.ellipse(cx, y, rr * 1.08, u0 * 0.2, 0, 0, Math.PI); g.fill();
        if (Math.sin(y * 31.4 + cx) > 0.45) { g.fillStyle = "rgba(255,226,170,0.7)"; g.fillRect(cx - rr * 0.6 + Math.sin(y) * rr * 0.4, y - u0 * 0.25, u0 * 0.35, u0 * 0.2); }
      }
    }
    g.restore();
    return;
    }
    if (which === "hilltower") {
    // ---- the tower on its hill: a dark wooded hill, the slim shaft, the round deck lit violet-blue, the mast
    const nx = W * (W > H ? 0.3 : 0.26), hillTop = horizon - Math.min(horizon * 0.52, H * 0.4), hw = W * (W > H ? 0.17 : 0.3);
    g.fillStyle = "#171a3a"; g.beginPath(); g.moveTo(nx - hw, horizon);
    const cy = horizon - (horizon - hillTop) / 0.75;                     // a cubic's peak reaches 3/4 of its controls' height
    g.bezierCurveTo(nx - hw * 0.45, cy, nx + hw * 0.45, cy, nx + hw, horizon); g.closePath(); g.fill();
    for (let k = 0; k < 40; k++) {                                       // the trees' path lights winding up the hill
      const t = k / 40, x = nx + Math.sin(t * 9) * hw * 0.35 * (1 - t), y = horizon - (horizon - hillTop) * t * 0.92;
      g.fillStyle = "rgba(255,214,150," + (0.25 + 0.4 * ((k * 7) % 3) / 2).toFixed(2) + ")"; g.fillRect(x, y, u0 * 0.22, u0 * 0.22);
    }
    const base = hillTop + u0 * 0.6, shaftTop = base - Math.min(horizon * 0.22, H * 0.16), deck = shaftTop - u0 * 2.2, mast = deck - Math.min(horizon * 0.12, H * 0.09);
    g.save(); g.shadowColor = "#a48cff"; g.shadowBlur = u0 * 2.4;
    const gr = g.createLinearGradient(0, mast, 0, base); gr.addColorStop(0, "#e9e4ff"); gr.addColorStop(0.4, "#9c8cf0"); gr.addColorStop(1, "#4b3f99");
    g.fillStyle = gr;
    g.beginPath(); g.moveTo(nx - u0 * 1.1, base); g.lineTo(nx - u0 * 0.55, shaftTop); g.lineTo(nx + u0 * 0.55, shaftTop); g.lineTo(nx + u0 * 1.1, base); g.closePath(); g.fill();
    g.fillStyle = "#d8d0ff"; g.fillRect(nx - u0 * 2.2, deck, u0 * 4.4, u0 * 2.2);                 // the observation deck drum
    g.fillStyle = "#7aa2f7"; g.fillRect(nx - u0 * 2.2, deck + u0 * 0.9, u0 * 4.4, u0 * 0.35);     // its ring of light
    g.fillStyle = "#c9c2ff"; g.fillRect(nx - u0 * 1.2, deck - u0 * 0.8, u0 * 2.4, u0 * 0.8);
    g.fillStyle = "#efeaff"; g.fillRect(nx - u0 * 0.22, mast, u0 * 0.44, deck - u0 * 0.8 - mast);   // the mast
    g.restore();
    beacons.push({ x: nx, y: mast + u0 * 0.3, r: u0 * 0.4 });
    return;
    }
    if (which === "tallglass") {
    // ---- the city's tallest, a slender tapered glass tower with softly curved sides; dark glass with
    // scattered lit floors and a pale seam, only its open crown glows (a building, not a beam of light)
    const lx = W * (W > H ? 0.73 : 0.75), lt = horizon - Math.min(horizon * 0.74, H * 0.56), lh = horizon - lt, b = u0 * 3.2, tip = u0 * 0.55;
    const half = (y) => tip + (b - tip) * Math.pow((y - lt) / lh, 0.62);                      // convex taper
    const outline = () => { g.beginPath(); g.moveTo(lx - b, horizon);
      for (let y = horizon; y >= lt; y -= u0 * 0.5) g.lineTo(lx - half(y), y);
      for (let y = lt; y <= horizon; y += u0 * 0.5) g.lineTo(lx + half(y), y); g.closePath(); };
    g.save();
    const gr = g.createLinearGradient(lx - b, 0, lx + b, 0);             // glass: darker at the edges, a cool sheen down the middle
    gr.addColorStop(0, "#141a3a"); gr.addColorStop(0.45, "#2c3a6e"); gr.addColorStop(0.55, "#33447c"); gr.addColorStop(1, "#11152e");
    g.fillStyle = gr; outline(); g.fill();
    g.save(); outline(); g.clip();
    for (let y = lt + lh * 0.14; y < horizon - u0; y += u0 * 0.9) {      // lit floors, a few windows each
      const hw = half(y);
      for (let x = lx - hw + u0 * 0.3; x < lx + hw - u0 * 0.3; x += u0 * 0.7)
        if (Math.sin(x * 78.233 + y * 12.9898) > 0.72) { g.fillStyle = "rgba(255,226,170,0.55)"; g.fillRect(x, y, u0 * 0.4, u0 * 0.3); }
    }
    g.fillStyle = "rgba(190,220,255,0.35)"; g.fillRect(lx - u0 * 0.06, lt + lh * 0.14, u0 * 0.12, lh * 0.86);   // the seam
    g.restore();
    g.shadowColor = "#9fd8ff"; g.shadowBlur = u0 * 1.6;                  // the crown: the top tenth lit pale blue
    const crown = lt + lh * 0.12;
    g.fillStyle = "rgba(200,232,255,0.85)"; g.beginPath(); g.moveTo(lx - half(crown), crown);
    for (let y = crown; y >= lt; y -= u0 * 0.4) g.lineTo(lx - half(y), y);
    for (let y = lt; y <= crown; y += u0 * 0.4) g.lineTo(lx + half(y), y); g.closePath(); g.fill();
    g.globalCompositeOperation = "destination-out"; g.shadowBlur = 0;     // the slit up the crown
    g.fillRect(lx - u0 * 0.12, lt + u0 * 0.5, u0 * 0.24, lh * 0.09);
    g.restore();
    beacons.push({ x: lx, y: lt + u0 * 0.2, r: u0 * 0.4 });
    return;
    }
    const u = Math.min(W, H * 1.2) / 100;                                 // a size unit that works on a phone and a desk
    if (which === "spire") {
    // ---- the tall tower: a tapering shaft, two decks, the spire; lit pale blue with purple accents
    const sx = W * (W > H ? 0.74 : 0.76), top = horizon - Math.min(horizon * 0.86, H * 0.66), hgt = horizon - top;
    const y1 = horizon - hgt * 0.56, y2 = horizon - hgt * 0.73, ys = horizon - hgt * 0.8;
    const b0 = u * 3.6, b1 = u * 1.25, b2 = u * 0.85;
    g.save();
    g.shadowColor = "#7dcfff"; g.shadowBlur = u * 2.2;
    let gr = g.createLinearGradient(0, top, 0, horizon);
    gr.addColorStop(0, "#9fd8ff"); gr.addColorStop(0.5, "#5b7fd6"); gr.addColorStop(1, "#2a2f6b");
    g.fillStyle = gr;
    g.beginPath();                                                        // shaft: a triangle base easing into a cylinder
    g.moveTo(sx - b0, horizon); g.quadraticCurveTo(sx - b1 * 1.05, horizon - hgt * 0.3, sx - b1, y1);
    g.lineTo(sx - b2, ys); g.lineTo(sx + b2, ys); g.lineTo(sx + b1, y1);
    g.quadraticCurveTo(sx + b1 * 1.05, horizon - hgt * 0.3, sx + b0, horizon); g.closePath(); g.fill();
    g.fillStyle = "#c9ecff";                                              // the two observation decks
    g.fillRect(sx - b1 * 1.9, y1 - u * 1.6, b1 * 3.8, u * 1.6);
    g.fillRect(sx - b2 * 1.7, y2 - u * 1.0, b2 * 3.4, u * 1.0);
    g.fillStyle = "#bb9af7"; g.fillRect(sx - b1 * 1.9, y1 - u * 0.3, b1 * 3.8, u * 0.3); g.fillRect(sx - b2 * 1.7, y2 - u * 0.25, b2 * 3.4, u * 0.25);
    g.fillStyle = "#e6f6ff"; g.fillRect(sx - u * 0.18, top, u * 0.36, ys - top);   // the spire
    g.shadowBlur = 0; g.strokeStyle = "rgba(20,24,60,0.45)"; g.lineWidth = Math.max(1, u * 0.12);
    for (let y = horizon - u * 2; y > y1 + u; y -= u * 1.6) {             // the lattice bands down the shaft
      const k = (horizon - y) / (horizon - y1), half = b0 + (b1 - b0) * Math.sqrt(k);
      g.beginPath(); g.moveTo(sx - half, y); g.lineTo(sx + half, y); g.stroke();
    }
    g.restore();
    beacons.push({ x: sx, y: top + u * 0.4, r: u * 0.45 }, { x: sx, y: y2 - u * 1.4, r: u * 0.3 });
    return;
    }
    // ---- the lattice tower: flared legs, main and top decks, antenna; lit warm orange
    const tx = W * (W > H ? 0.27 : 0.22), th = Math.min(horizon * 0.66, H * 0.5), tt = horizon - th;
    const leg = u * 7.5, neck = u * 0.9, d1 = horizon - th * 0.38, d2 = horizon - th * 0.66, ant = horizon - th * 0.8;
    const wAt = (y) => { const k = (horizon - y) / (ant - tt + (horizon - ant)); return neck + (leg - neck) * Math.pow(1 - Math.min(1, (horizon - y) / (horizon - ant)), 1.7); };
    g.save();
    g.shadowColor = "#ff9e64"; g.shadowBlur = u * 2.6;
    const gr = g.createLinearGradient(0, tt, 0, horizon);
    gr.addColorStop(0, "#ffd2a8"); gr.addColorStop(0.45, "#ff9e64"); gr.addColorStop(1, "#d9542b");
    g.fillStyle = gr;
    g.beginPath(); g.moveTo(tx - leg, horizon);
    for (let y = horizon; y >= ant; y -= u * 0.5) g.lineTo(tx - wAt(y), y);
    for (let y = ant; y <= horizon; y += u * 0.5) g.lineTo(tx + wAt(y), y);
    g.closePath(); g.fill();
    g.globalCompositeOperation = "destination-out";                       // the arch between the legs
    g.beginPath(); g.moveTo(tx - leg * 0.62, horizon); g.quadraticCurveTo(tx, horizon - th * 0.26, tx + leg * 0.62, horizon); g.closePath(); g.fill();
    g.globalCompositeOperation = "source-over";
    g.shadowBlur = 0; g.strokeStyle = "rgba(40,16,10,0.55)"; g.lineWidth = Math.max(1, u * 0.14);
    for (let y = horizon - u * 1.2; y > ant; y -= u * 1.3) {               // the lattice: cross-braces up the legs
      const w0 = wAt(y), w1 = wAt(y - u * 1.3);
      g.beginPath(); g.moveTo(tx - w0, y); g.lineTo(tx + w1, y - u * 1.3); g.moveTo(tx + w0, y); g.lineTo(tx - w1, y - u * 1.3); g.stroke();
    }
    g.shadowColor = "#ff9e64"; g.shadowBlur = u * 1.5; g.fillStyle = "#fff1dc";   // main deck and top deck
    g.fillRect(tx - wAt(d1) * 1.6, d1 - u * 1.5, wAt(d1) * 3.2, u * 1.5);
    g.fillRect(tx - wAt(d2) * 1.9, d2 - u * 0.9, wAt(d2) * 3.8, u * 0.9);
    g.fillStyle = "#ffe2c4"; g.fillRect(tx - u * 0.22, tt, u * 0.44, ant - tt);    // the antenna
    g.restore();
    beacons.push({ x: tx, y: tt + u * 0.3, r: u * 0.4 }, { x: tx - wAt(d2) * 1.6, y: d2 - u * 1.1, r: u * 0.25 }, { x: tx + wAt(d2) * 1.6, y: d2 - u * 1.1, r: u * 0.25 });
  }

  let FONT = CJK_FONT;                 // start() picks the Latin stack for the American cities
  function hexA(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return "rgba(" + (n >> 16 & 255) + "," + (n >> 8 & 255) + "," + (n & 255) + "," + a.toFixed(3) + ")";
  }

  // only two or three failing tubes in the whole scene (more reads as broken): the nearest, brightest signs on
  // screen, one of them with a single bad character instead of the whole sign; a burst every 15-40 s each
  function pickFlickers() {
    for (const s of signs) { s.flick = false; s.dead = -1; s.next = 0; s.burstEnd = 0; }
    const pool = signs.filter((s) => !s.board && s.text && s.y >= 0 && s.y + s.h <= horizon + H * 0.1)
                      .sort((a, b) => (b.glow || 1) * b.h - (a.glow || 1) * a.h).slice(0, 8);
    const n = Math.min(pool.length, 2 + (Math.random() < 0.5 ? 1 : 0));
    for (let i = 0; i < n; i++) {
      const s = pool.splice(Math.floor(Math.random() * pool.length), 1)[0];
      s.flick = true;
      if (i === 0 && s.vertical && [...s.text].length > 1) s.dead = Math.floor(Math.random() * [...s.text].length);
    }
  }

  function drawSigns(t) {
    ctx.save();
    for (const s of signs) {
      if (s.block) continue;
      let a = 1, burst = false;
      if (s.flick && mode === "rain") {          // a failing tube: steady for a long while, then a short irregular burst
        if (!s.next) s.next = t + 4000 + Math.random() * 16000;
        if (t >= s.next) { s.burstEnd = t + 150 + Math.random() * 650; s.next = s.burstEnd + 15000 + Math.random() * 25000; }
        burst = t < s.burstEnd;
        if (burst && s.dead < 0) a = Math.random() < 0.55 ? 0.12 : (Math.random() < 0.5 ? 0.6 : 1);
      }
      ctx.globalAlpha = 0.95 * a * (s.glow || 1);
      ctx.shadowColor = s.col; ctx.shadowBlur = 22 * dpr * (s.glow || 1);
      if (s.board) {
        const gr = ctx.createLinearGradient(s.x, s.y, s.x + s.w, s.y + s.h);
        gr.addColorStop(0, hexA(s.col, 0.85)); gr.addColorStop(1, hexA(s.col2, 0.85));
        ctx.fillStyle = gr; ctx.fillRect(s.x, s.y, s.w, s.h);
        ctx.shadowBlur = 0; ctx.fillStyle = "rgba(10,11,28,0.25)";
        for (let y = s.y + 2 * dpr; y < s.y + s.h; y += 4 * dpr) ctx.fillRect(s.x, y, s.w, 1.2 * dpr);
        continue;
      }
      if (s.side) {                                                       // the bracket holding it off the wall
        ctx.save(); ctx.shadowBlur = 0; ctx.fillStyle = "rgba(40,44,70,0.9)";
        const bx0 = Math.min(s.bx, s.side < 0 ? s.x + s.w : s.x), bx1 = Math.max(s.bx, s.side < 0 ? s.x + s.w : s.x);
        ctx.fillRect(bx0, s.y + s.h * 0.12, bx1 - bx0 + 1, 2 * dpr); ctx.fillRect(bx0, s.y + s.h * 0.85, bx1 - bx0 + 1, 2 * dpr);
        ctx.restore();
      }
      if (s.lightbox) {                                                   // a white lightbox with dark lettering
        ctx.shadowColor = "#fff6e0"; ctx.shadowBlur = 14 * dpr * (s.glow || 1);
        ctx.fillStyle = "#f4f1e8"; ctx.fillRect(s.x, s.y, s.w, s.h);
        ctx.shadowBlur = 0; ctx.strokeStyle = "rgba(20,20,30,0.6)"; ctx.lineWidth = Math.max(1, s.w * 0.04); ctx.strokeRect(s.x, s.y, s.w, s.h);
      } else {
        ctx.fillStyle = "rgba(10,11,28,0.85)"; ctx.strokeStyle = s.col; ctx.lineWidth = 1.5 * dpr;
        ctx.fillRect(s.x, s.y, s.w, s.h); ctx.strokeRect(s.x, s.y, s.w, s.h);
      }
      ctx.fillStyle = s.col; ctx.font = "700 " + s.fs + "px " + FONT;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      if (s.vertical) [...s.text].forEach((ch, i) => {
        if (i === s.dead && burst && Math.random() < 0.55) { ctx.save(); ctx.globalAlpha *= 0.15; ctx.shadowBlur = 0;
          ctx.fillText(ch, s.x + s.w / 2, s.y + s.fs * 0.9 + i * s.fs * 1.08); ctx.restore(); return; }   // one bad character sputters
        ctx.fillText(ch, s.x + s.w / 2, s.y + s.fs * 0.9 + i * s.fs * 1.08);
      });
      else ctx.fillText(s.text, s.x + s.w / 2, s.y + s.h / 2);
    }
    ctx.restore();
  }

  // ---- the scene (city or alley): signs flicker, beacons blink; no rain here (the rain is its own overlay below) ----
  // now and then someone in the front row switches a light off (subtle, not too often): one window every 10-30 s,
  // dark for 40 s to 3 min, then back on
  function lightsOut(t) {
    if (mode !== "rain" || !wins.length) return;
    if (!nextDark) nextDark = t + 8000 + Math.random() * 12000;
    if (t >= nextDark) {
      const w = wins[Math.floor(Math.random() * wins.length)];
      if (!dark.some((d) => d.w === w)) dark.push({ w, until: t + 40000 + Math.random() * 140000 });
      nextDark = t + 10000 + Math.random() * 20000;
    }
    dark = dark.filter((d) => d.until > t);
    for (const d of dark) { ctx.fillStyle = d.w.col; ctx.fillRect(d.w.x, d.w.y, d.w.w, d.w.h); }
  }

  function frame(t) {
    ctx.drawImage(city, 0, 0);
    if (!["alley", "osaka", "stray"].includes(scene)) lightsOut(t);
    drawSigns(t);
    if (fore) ctx.drawImage(fore, 0, 0);                                  // bridge, palms, the L: in front of the signs
    if (extras.length) drawExtras(t);
    const on = mode !== "rain" || (t % 2400) < 1000;
    if (on) { ctx.save(); for (const b of beacons) { ctx.fillStyle = "#ff4d5e"; ctx.shadowColor = "#ff4d5e"; ctx.shadowBlur = b.r * 6; ctx.beginPath(); ctx.arc(b.x, b.y, b.r, 0, Math.PI * 2); ctx.fill(); } ctx.restore(); }
    ctx.fillStyle = "rgba(122,162,247,0.035)"; ctx.fillRect(0, 0, W, H);          // a faint mist over everything
  }
  function loop(t) {
    raf = requestAnimationFrame(loop);
    if (t - last < 33) return;                       // ~30 fps
    last = t; frame(t);
  }

  let cssW = 0;
  function resize(force) {
    if (!canvas) return;
    // the canvas is 100lvh tall (the viewport with the browser's toolbars hidden), so a phone's toolbars sliding in and
    // out while scrolling never change it; only a new width (rotation, a desktop window) rebuilds the scene
    const w = canvas.clientWidth || innerWidth, h = canvas.clientHeight || Math.max(innerHeight, screen.height || 0);
    if (force !== true && w === cssW) return;
    cssW = w;
    dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    W = canvas.width = Math.round(w * dpr); H = canvas.height = Math.round(h * dpr);
    if (["alley", "osaka", "stray"].includes(scene)) buildAlley(); else buildCity();
    pickFlickers();
    if (mode !== "rain" || document.hidden) frame(performance.now());
  }

  const SCENES = ["city", "alley", "seoul", "sf", "la", "chicago", "br", "hk", "sh", "tp", "sg", "lv", "bkk", "akira", "osaka", "stray"];
  // start(scene, words): a scene's name (else "city"), the page's words for the signs. Animated unless reduced motion.
  function start(sc, words) {
    stop();
    const LATIN = ["sf", "la", "chicago", "sg", "lv", "stray"], ZH = ["hk", "sh", "tp", "bkk"];
    scene = SCENES.includes(sc) ? sc : "city";
    FONT = ["sf", "la", "chicago", "lv", "stray"].includes(scene) ? LATIN_FONT : CJK_FONT;
    const base = US_WORDS[scene] || MORE_WORDS[scene] || (scene === "seoul" ? KO_TECH : scene === "br" ? BR_WORDS : TECH);
    const kana = /[\u3040-\u30ff]/;
    const own = [...new Set((words || []).map((w) => {
      const k = String(w).toLowerCase().replace(/[^a-z0-9]/g, "");
      if (LATIN.includes(scene)) return String(w).toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 9) || null;
      if (scene === "seoul") return HANGUL[k];
      const kj = KANJI[k];
      return ZH.includes(scene) && kj && kana.test(kj) ? null : kj;      // a Chinese city: no Japanese kana
    }).filter((w) => w && (w.length >= 2 || /[^\x00-\x7f]/.test(w))))];
    SIGNS = (own.length ? own.concat(own, base) : base).concat(scene === "alley" ? ALLEY_FOOD : []);   // the page's words twice as likely as the rest
    HSIGNS = scene === "bkk" ? THAI : SIGNS;                                // facade boards (Thai can't stack vertically)
    mode = matchMedia("(prefers-reduced-motion: reduce)").matches ? "still" : "rain";
    canvas = document.getElementById("bg");
    if (!canvas) { canvas = document.createElement("canvas"); canvas.id = "bg"; canvas.setAttribute("aria-hidden", "true"); document.body.prepend(canvas); }
    ctx = canvas.getContext("2d");
    cssW = 0; resize(true);
    addEventListener("resize", onResize);
    document.addEventListener("visibilitychange", onVis);
    if (mode === "rain" && !document.hidden) raf = requestAnimationFrame(loop); else frame(performance.now());
  }
  let rt = 0;
  function onResize() { clearTimeout(rt); rt = setTimeout(resize, 150); }
  function onVis() { cancelAnimationFrame(raf); if (canvas && mode === "rain" && !document.hidden) raf = requestAnimationFrame(loop); }
  function stop() {
    cancelAnimationFrame(raf); raf = 0; clearTimeout(rt);
    removeEventListener("resize", onResize); document.removeEventListener("visibilitychange", onVis);
    const c = document.getElementById("bg"); if (c) c.remove();
    canvas = ctx = city = fore = null; mode = null; beacons = []; signs = []; extras = []; wins = []; dark = []; horizon = 0;
  }

  // ---- the rain: its own canvas (#rainfx) over whatever background is on, a scene or the viewer's picture or
  // video, or none. Over a scene the drops splash on its street (below its horizon); elsewhere they just fall.
  const R = { canvas: null, ctx: null, raf: 0, last: 0, drops: [], splashes: [], W: 0, H: 0, dpr: 1, cssW: 0, still: false };
  function rainDrop(anywhere) {
    const z = Math.random(), d = R.dpr;                 // depth: far drops are short, faint and slow
    return { x: Math.random() * R.W * 1.2 - R.W * 0.1, y: anywhere ? Math.random() * R.H : -20 * d,
             len: (8 + z * 22) * d, v: (9 + z * 16) * d, a: 0.12 + z * 0.35, w: (0.6 + z * 0.9) * d };
  }
  function rainSize(force) {
    if (!R.canvas) return;
    const w = R.canvas.clientWidth || innerWidth, h = R.canvas.clientHeight || innerHeight;
    if (force !== true && w === R.cssW) return;
    R.cssW = w; R.dpr = Math.min(window.devicePixelRatio || 1, 1.5);
    R.W = R.canvas.width = Math.round(w * R.dpr); R.H = R.canvas.height = Math.round(h * R.dpr);
    R.drops = Array.from({ length: Math.round(R.W * R.H / (R.dpr * R.dpr) / 2600) }, () => rainDrop(true));
    if (R.still || document.hidden) rainFrame();
  }
  function rainFrame() {
    const c = R.ctx, slant = 0.18;
    c.clearRect(0, 0, R.W, R.H);
    c.save(); c.lineCap = "round";
    const ground = canvas && horizon ? horizon / H * R.H : 0;          // the scene's street, in this canvas's pixels
    for (const d of R.drops) {
      c.strokeStyle = "rgba(170,190,255," + d.a + ")"; c.lineWidth = d.w;
      c.beginPath(); c.moveTo(d.x, d.y); c.lineTo(d.x - d.len * slant, d.y + d.len); c.stroke();
      if (R.still) continue;
      d.y += d.v; d.x -= d.v * slant;
      const floor = ground ? ground + Math.random() * (R.H - ground) : R.H + 20 * R.dpr;
      if (d.y > floor) {
        if (ground && Math.random() < 0.25) R.splashes.push({ x: d.x, y: d.y, r: 1, a: 0.5 });
        Object.assign(d, rainDrop(false));
      }
    }
    for (const s of R.splashes) {
      c.strokeStyle = "rgba(170,190,255," + s.a + ")"; c.lineWidth = 0.8 * R.dpr;
      c.beginPath(); c.ellipse(s.x, s.y, s.r * R.dpr * 2.2, s.r * R.dpr * 0.7, 0, 0, Math.PI * 2); c.stroke();
      s.r += 0.6; s.a -= 0.035;
    }
    R.splashes = R.splashes.filter((s) => s.a > 0);
    c.restore();
  }
  function rainLoop(t) {
    R.raf = requestAnimationFrame(rainLoop);
    if (t - R.last < 33) return;
    R.last = t; rainFrame();
  }
  let rrt = 0;
  function rainOnResize() { clearTimeout(rrt); rrt = setTimeout(rainSize, 150); }
  function rainOnVis() { cancelAnimationFrame(R.raf); if (R.canvas && !R.still && !document.hidden) R.raf = requestAnimationFrame(rainLoop); }
  function rain(on) {
    cancelAnimationFrame(R.raf); R.raf = 0; clearTimeout(rrt);
    removeEventListener("resize", rainOnResize); document.removeEventListener("visibilitychange", rainOnVis);
    const old = document.getElementById("rainfx"); if (old) old.remove();
    R.canvas = R.ctx = null; R.splashes = []; R.drops = [];
    if (!on) return;
    R.still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    R.canvas = document.createElement("canvas"); R.canvas.id = "rainfx"; R.canvas.setAttribute("aria-hidden", "true");
    document.body.prepend(R.canvas);
    R.ctx = R.canvas.getContext("2d");
    R.cssW = 0; rainSize(true);
    addEventListener("resize", rainOnResize); document.addEventListener("visibilitychange", rainOnVis);
    if (!R.still && !document.hidden) R.raf = requestAnimationFrame(rainLoop); else rainFrame();
  }
  window.annaiBg = { start, stop, rain, scenes: SCENES.slice() };
})();
