// Zero-dependency static server + JSON-API proxy for the two-leg-repo demo.
// Serves the UI same-origin and mints per-party dev tokens server-side, so the
// browser needs neither CORS nor JWT crypto.  Node >= 18 (global fetch). No build.
//
//   node ui/serve.mjs   ->   http://localhost:8080
//
// Party ids + package id live in ui/demo-config.json, rewritten by ui/reseed.sh,
// and re-read on every request — so `bash ui/reseed.sh` + browser reload resets
// the whole demo with no server restart and no code edits.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createHmac } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DIR = dirname(fileURLToPath(import.meta.url));
const JSON_API = 'http://localhost:7575';
const PORT = 8080;
const TYPES = ['Assets:Bond', 'Assets:Cash', 'Repo:RepoProposal', 'Repo:RepoAgreement', 'Repo:EligibilityCriteria'];

const config = async () => JSON.parse(await readFile(join(DIR, 'demo-config.json'), 'utf8'));
const b64url = (s) => Buffer.from(s).toString('base64url');

function mintToken(ledgerId, party) {
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const p = b64url(JSON.stringify({
    'https://daml.com/ledger-api': { ledgerId, applicationId: 'demo-ui', actAs: [party], readAs: [party] },
  }));
  const s = createHmac('sha256', 'secret').update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${s}`;
}

async function callApi(cfg, role, path, body) {
  const party = cfg.parties[role];
  const res = await fetch(JSON_API + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${mintToken(cfg.ledgerId, party)}` },
    body: JSON.stringify(body),
  });
  return res.json();
}

const readBody = (req) => new Promise((resolve, reject) => {
  let d = ''; req.on('data', (c) => (d += c));
  req.on('end', () => { try { resolve(d ? JSON.parse(d) : {}); } catch (e) { reject(e); } });
  req.on('error', reject);
});
const send = (res, code, obj) => { res.writeHead(code, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(obj)); };

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(await readFile(join(DIR, 'index.html')));
    }
    const cfg = await config();
    if (url.pathname === '/api/config') {
      return send(res, 200, { roles: Object.keys(cfg.parties), parties: cfg.parties, pkg: cfg.pkg });
    }
    if (url.pathname === '/api/holdings') {
      const role = url.searchParams.get('party');
      if (!cfg.parties[role]) return send(res, 400, { error: 'unknown role' });
      const data = await callApi(cfg, role, '/v1/query', { templateIds: TYPES.map((t) => `${cfg.pkg}:${t}`) });
      return send(res, 200, { role, party: cfg.parties[role], ...data });
    }
    if (req.method === 'POST' && url.pathname === '/api/exercise') {
      const b = await readBody(req); // { party, templateId, contractId, choice, argument }
      const data = await callApi(cfg, b.party, '/v1/exercise', {
        templateId: `${cfg.pkg}:${b.templateId}`, contractId: b.contractId, choice: b.choice, argument: b.argument || {},
      });
      return send(res, 200, data);
    }
    if (req.method === 'POST' && url.pathname === '/api/create') {
      const b = await readBody(req); // { party, templateId, payload }
      const data = await callApi(cfg, b.party, '/v1/create', { templateId: `${cfg.pkg}:${b.templateId}`, payload: b.payload });
      return send(res, 200, data);
    }
    res.writeHead(404); res.end('not found');
  } catch (e) {
    send(res, 500, { error: String((e && e.message) || e) });
  }
});
server.listen(PORT, () => console.log(`two-leg-repo demo UI  ->  http://localhost:${PORT}`));
