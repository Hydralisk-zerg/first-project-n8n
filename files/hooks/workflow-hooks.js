/** External Hooks: correct nested structure expected by n8n
 * Export object { workflow: { create: [fn], update: [fn], save: [fn] } }
 */
const fs = require('fs');
const path = require('path');
const DIR = '/files/workflows';

function ensureDir() { try { fs.mkdirSync(DIR, { recursive: true }); } catch (_) {} }
function fileSafe(name) {
  return String(name || '')
    .replace(/[^a-z0-9\-_\.]/gi, '_')
    .replace(/_+/g, '_')
    .slice(0, 70);
}
function persist(raw) {
  const wf = raw?.workflow || raw?.workflowData || raw; // version differences
  if (!wf || !wf.id) return;
  ensureDir();
  const out = path.join(DIR, `${fileSafe(wf.id + '-' + wf.name)}.json`);
  try { fs.writeFileSync(out, JSON.stringify(wf, null, 2), 'utf8'); } catch (_) {}
}

module.exports = {
  workflow: {
    create: [ (data) => persist(data) ],
    update: [ (data) => persist(data) ],
    save:   [ (data) => persist(data) ],
  },
};
