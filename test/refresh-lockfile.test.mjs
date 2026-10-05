import assert from 'node:assert/strict'
import { execFile, execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import http from 'node:http'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { promisify } from 'node:util'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const execute = promisify(execFile)
const script = fileURLToPath(new URL('../scripts/update.sh', import.meta.url))
const binary = process.env.PNPM_TEST_BINARY ?? 'pnpm'

for (const linker of ['isolated', 'loaded']) {
  test(`refresh-lockfile resolves newer matching versions with ${linker}`, async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'update-refresh-'))
    let registry
    try {
      const workspace = path.join(root, 'workspace')
      await mkdir(workspace)
      const artifacts = {}
      for (const version of ['1.0.0', '1.1.0']) {
        const packageRoot = path.join(root, version, 'package')
        await mkdir(packageRoot, { recursive: true })
        await writeFile(path.join(packageRoot, 'package.json'), JSON.stringify({ name: 'refresh-fixture', version }))
        const archive = path.join(root, `${version}.tgz`)
        execFileSync('tar', ['-czf', archive, '-C', path.dirname(packageRoot), 'package'])
        artifacts[version] = await readFile(archive)
      }
      let published = ['1.0.0']
      registry = http.createServer((request, response) => {
        const version = request.url.match(/^\/(1\.[01]\.0)\.tgz$/)?.[1]
        if (version) {
          response.end(artifacts[version])
          return
        }
        if (request.url !== '/refresh-fixture') {
          response.writeHead(404).end()
          return
        }
        const origin = `http://127.0.0.1:${registry.address().port}`
        response.setHeader('Content-Type', 'application/json')
        response.setHeader('Cache-Control', 'no-store')
        response.end(JSON.stringify({
          name: 'refresh-fixture',
          'dist-tags': { latest: published.at(-1) },
          time: Object.fromEntries(published.map(version => [version, '2020-01-01T00:00:00.000Z'])),
          versions: Object.fromEntries(published.map(version => [version, {
            name: 'refresh-fixture', version,
            dist: { tarball: `${origin}/${version}.tgz`, integrity: `sha512-${createHash('sha512').update(artifacts[version]).digest('base64')}` },
          }])),
        }))
      })
      await new Promise(resolve => registry.listen(0, '127.0.0.1', resolve))
      await writeFile(path.join(workspace, 'package.json'), JSON.stringify({ name: 'workspace', dependencies: { 'refresh-fixture': '^1.0.0' } }))
      await writeFile(path.join(workspace, '.npmrc'), `registry=http://127.0.0.1:${registry.address().port}\n`)
      const cache = path.join(root, 'cache')
      await writeFile(path.join(workspace, 'pnpm-workspace.yaml'), [
        `nodeLinker: ${linker === 'loaded' ? '{ type: loaded }' : 'isolated'}`,
        `storeDir: ${path.join(root, 'store')}`, `cacheDir: ${cache}`,
        'minimumReleaseAge: 0', 'ignoreScripts: true',
      ].join('\n') + '\n')
      const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !/^(npm_config_|pnpm_config_)/i.test(key)))
      const bin = path.join(root, 'bin')
      await mkdir(bin)
      const resolvedBinary = binary === 'pnpm' ? execFileSync('which', ['pnpm'], { encoding: 'utf8' }).trim() : path.resolve(binary)
      await writeFile(path.join(bin, 'pnpm'), `#!/usr/bin/env bash\nexec '${resolvedBinary.replaceAll("'", "'\\''")}' "$@"\n`, { mode: 0o755 })
      env.PATH = `${bin}${path.delimiter}${env.PATH}`
      const options = { cwd: workspace, env, timeout: 60000 }
      await execute('pnpm', ['install'], options)
      const oldLockfile = await readFile(path.join(workspace, 'pnpm-lock.yaml'), 'utf8')
      assert.match(oldLockfile, /refresh-fixture@1\.0\.0/)
      published = ['1.0.0', '1.1.0']
      await rm(cache, { recursive: true, force: true })
      await execute('bash', [script], { ...options, env: { ...env,
        UPDATE_PNPM: 'false', NODE: 'false', UPDATE_DEPS: 'false', REFRESH_LOCKFILE: 'true',
        INCLUDE_GITHUB_ACTIONS: 'false', CHANGESETS: 'false', EXCLUDE: '',
      } })
      const newLockfile = await readFile(path.join(workspace, 'pnpm-lock.yaml'), 'utf8')
      assert.match(newLockfile, /refresh-fixture@1\.1\.0/)
      assert.doesNotMatch(newLockfile, /refresh-fixture@1\.0\.0/)
    } finally {
      if (registry) await new Promise(resolve => registry.close(resolve))
      await rm(root, { recursive: true, force: true })
    }
  })
}
