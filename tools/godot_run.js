// Lancia Godot con un SEMAFORO GLOBALE: un solo processo Godot alla volta su questo PC (che va in crash sotto carico).
// Uso:  node tools/godot_run.js [--timeout=120] -- <argomenti per godot>
// Es.:  node tools/godot_run.js -- --headless --path . --script tests/check_data.gd
//       node tools/godot_run.js -- --path . res://scenes/battle.tscn --resolution 960x540 -- --shot=docs/screens/x.png --frames=90
const fs = require('fs'), path = require('path'), { spawn } = require('child_process');
const GODOT = 'C:/Users/villa/Downloads/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe';
const LOCK = path.join(__dirname, '..', '.godot_lock');
const argv = process.argv.slice(2);
const sep = argv.indexOf('--');
const own = sep >= 0 ? argv.slice(0, sep) : [];
const gargs = sep >= 0 ? argv.slice(sep + 1) : argv;
let timeout = 120;
for (const a of own) if (a.startsWith('--timeout=')) timeout = +a.slice(10);
const STALE = 10 * 60 * 1000;
function tryLock() {
  try { fs.mkdirSync(LOCK); fs.writeFileSync(path.join(LOCK, 'owner'), String(process.pid) + ' ' + new Date().toISOString()); return true; }
  catch (e) {
    try { const st = fs.statSync(LOCK); if (Date.now() - st.mtimeMs > STALE) { fs.rmSync(LOCK, { recursive: true, force: true }); } } catch (_) {}
    // semaforo orfano: il processo node che lo teneva non esiste più
    try {
      const pid = parseInt(fs.readFileSync(path.join(LOCK, 'owner'), 'utf8'), 10);
      if (pid > 0) { try { process.kill(pid, 0); } catch (e2) { if (e2.code === 'ESRCH') fs.rmSync(LOCK, { recursive: true, force: true }); } }
    } catch (_) {}
    return false;
  }
}
function release() { try { fs.rmSync(LOCK, { recursive: true, force: true }); } catch (_) {} }
const t0 = Date.now();
(function wait() {
  if (!tryLock()) {
    if (Date.now() - t0 > 15 * 60 * 1000) { console.error('[godot_run] semaforo occupato da troppo tempo'); process.exit(3); }
    return setTimeout(wait, 1500);
  }
  const waited = ((Date.now() - t0) / 1000).toFixed(1);
  if (+waited > 2) console.log('[godot_run] atteso il semaforo ' + waited + ' s');
  const p = spawn(GODOT, gargs, { stdio: 'inherit', cwd: process.cwd() });
  const killer = setTimeout(() => { console.error('[godot_run] TIMEOUT ' + timeout + ' s, termino Godot'); p.kill(); }, timeout * 1000);
  const done = code => { clearTimeout(killer); release(); process.exit(code == null ? 1 : code); };
  p.on('exit', done); p.on('error', e => { console.error(e); done(1); });
  process.on('SIGINT', () => { p.kill(); release(); process.exit(130); });
})();
