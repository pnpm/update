import { execFileSync } from 'node:child_process'
import { rmSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'

const config = JSON.parse(execFileSync('pnpm', ['config', 'list', '--json'], { encoding: 'utf8' }))
const setting = (camel, kebab) => config[camel] ?? config[kebab]
const linker = setting('nodeLinker', 'node-linker')
const loaded = (typeof linker === 'object' ? linker?.type : linker) === 'loaded'
const modules = resolvePath(setting('modulesDir', 'modules-dir') ?? (loaded ? '.pnpm' : 'node_modules'))
const virtualStore = setting('virtualStoreDir', 'virtual-store-dir')
const globalStore = loaded || setting('enableGlobalVirtualStore', 'enable-global-virtual-store') === true
const state = virtualStore && !globalStore ? resolvePath(virtualStore) : path.join(modules, '.pnpm')

rmSync(path.join(state, 'lock.yaml'), { force: true })
rmSync('pnpm-lock.yaml', { force: true })
rmSync('node_modules', { recursive: true, force: true })

function resolvePath(value) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('The installation directory must be a nonempty path')
  }
  return path.resolve(value.startsWith('~/') ? path.join(homedir(), value.slice(2)) : value)
}
