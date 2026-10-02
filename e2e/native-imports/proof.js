import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { closeSync, existsSync, openSync, readSync, statSync } from 'node:fs'
import path from 'node:path'

// Read-only evidence from the actual stand, independent of browser DOM counters.
export function database(sql) {
  const name = process.env.NATIVE_IMPORTS_DATABASE_NAME
  if (!name || !/^dawarich_(test|e2e)_a7_/.test(name)) {
    throw new Error('An explicitly named isolated A7 test database is required')
  }
  const env = {
    ...process.env,
    PGHOST: process.env.DATABASE_HOST || process.env.PGHOST,
    PGPORT: process.env.DATABASE_PORT || process.env.PGPORT,
    PGUSER: process.env.DATABASE_USERNAME || process.env.PGUSER,
    PGPASSWORD: process.env.DATABASE_PASSWORD || process.env.PGPASSWORD,
    PGDATABASE: name,
    PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=5000',
  }
  const text = execFileSync(process.env.NATIVE_IMPORTS_PSQL || 'psql',
    ['-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-c', sql], { env, encoding: 'utf8' }).trim()
  return text ? JSON.parse(text) : null
}

export function importEvidence(id) {
  if (!/^[1-9]\d*$/.test(String(id))) throw new Error('Invalid import id')
  return database(`
    SELECT json_build_object(
      'id', i.id, 'name', i.name, 'status', i.status, 'source', i.source,
      'processed', i.processed, 'points_count', i.points_count,
      'actual_points', (SELECT count(*) FROM points p WHERE p.import_id=i.id),
      'owner_email', u.email, 'locale', u.settings->>'locale',
      'blob_filename', b.filename, 'blob_metadata', b.metadata, 'blob_key', b.key,
      'blob_checksum', b.checksum,
      'blob_bytes', b.byte_size,
      'commands', COALESCE((SELECT json_agg(json_build_object(
        'type', o.command_type, 'version', o.command_version, 'payload', o.payload,
        'state', o.state, 'worker', j.worker, 'job_state', j.state,
        'handler', pc.handler, 'metadata', o.metadata))
        FROM job_outbox o LEFT JOIN oban.oban_jobs j ON j.id=o.oban_job_id
        LEFT JOIN phoenix.processed_commands pc ON pc.event_id=o.event_id
        WHERE o.command_type='imports.process_gpx' AND o.aggregate_id=i.id), '[]'::json)
    ) FROM imports i JOIN users u ON u.id=i.user_id
    LEFT JOIN active_storage_attachments a
      ON a.record_type='Import' AND a.record_id=i.id AND a.name='file'
    LEFT JOIN active_storage_blobs b ON b.id=a.blob_id WHERE i.id=${id}
  `)
}

export function storedBlobEvidence(blob) {
  const root = process.env.NATIVE_IMPORTS_STORAGE_ROOT
  if (!root || !path.isAbsolute(root)) throw new Error('Set isolated NATIVE_IMPORTS_STORAGE_ROOT')
  if (!/^[a-zA-Z0-9_-]+$/.test(blob.blob_key)) throw new Error('Invalid stored blob key')
  const file = path.join(root, blob.blob_key.slice(0, 2), blob.blob_key.slice(2, 4), blob.blob_key)
  if (!existsSync(file)) throw new Error('Actual uploaded blob is absent from the stand storage')
  const fd = openSync(file, 'r')
  const chunk = Buffer.alloc(65536)
  const digest = createHash('md5')
  let magic
  try {
    for (;;) {
      const count = readSync(fd, chunk)
      if (!count) break
      if (!magic) magic = chunk.subarray(0, 4).toString('hex')
      digest.update(chunk.subarray(0, count))
    }
  } finally { closeSync(fd) }
  return { magic, bytes: statSync(file).size, checksum: digest.digest('base64') }
}

export function deletionEvidence(id) {
  if (!/^[1-9]\d*$/.test(String(id))) throw new Error('Invalid import id')
  return database(`SELECT json_build_object(
    'imports', (SELECT count(*) FROM imports WHERE id=${id}),
    'points', (SELECT count(*) FROM points WHERE import_id=${id}),
    'attachments', (SELECT count(*) FROM active_storage_attachments
      WHERE record_type='Import' AND record_id=${id}))`)
}

export function downloadCommandEvidence(id) {
  if (!/^[1-9]\d*$/.test(String(id))) throw new Error('Invalid import id')
  return database(`SELECT COALESCE(json_agg(json_build_object(
    'type',o.command_type,'version',o.command_version,'payload',o.payload,
    'job_state',j.state,'worker',j.worker,'handler',pc.handler)), '[]'::json)
    FROM job_outbox o LEFT JOIN oban.oban_jobs j ON j.id=o.oban_job_id
    LEFT JOIN phoenix.processed_commands pc ON pc.event_id=o.event_id
    WHERE o.command_type='imports.prepare_download' AND o.aggregate_id=${id}`)
}
