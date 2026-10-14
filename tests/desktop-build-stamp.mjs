import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const [source, stampFile, version, revision, checkPhaseFile, nativeCopyPhaseFile] = process.argv.slice(2)
const manifest = JSON.parse(readFileSync(join(source, 'apps/desktop/package.json'), 'utf8'))
for (const [, name] of readFileSync(checkPhaseFile, 'utf8').matchAll(/npm run ([\w:-]+)/g)) {
  assert.ok(Object.hasOwn(manifest.scripts, name), `desktop checkPhase references absent script: ${name}`)
}
const script = readFileSync(join(source, 'apps/desktop/scripts/bundle-electron-main.mjs'), 'utf8')
const functions = script.match(/function productIdentity\(source, stamp\) \{[\s\S]*?\n\}/g)
assert.equal(functions?.length, 1, 'extract exactly one actual bundler identity function')
const identity = new Function('execFileSync', 'join', `return (${functions[0]})`)(execFileSync, join)
const stamp = JSON.parse(readFileSync(stampFile, 'utf8'))
assert.throws(() => identity(source, { ...stamp, payload: undefined }), /Invalid desktop stamp payload/)
assert.throws(() => identity(source, { ...stamp, payload: 'invalid' }), /Invalid desktop stamp payload/)
const product = JSON.parse(identity(source, stamp))
assert.equal(product.cliName, 'hermes')
assert.equal(stamp.schemaVersion, 2)
assert.equal(stamp.payload, 'bootstrap')
assert.equal(stamp.baseVersion, version)
assert.equal(stamp.displayVersion, version)
assert.equal(stamp.commit, revision)
assert.equal(stamp.source, 'nix')
assert.equal(stamp.distribution, 'nix')
assert.equal(stamp.updateMechanism, 'external')

// Synthetic prepared inputs test layout only, not native compilation or execution.
const fixture = mkdtempSync(join(process.cwd(), 'native-layout-'))
mkdirSync(join(fixture, 'build/native-deps/node-pty/build/Release'), { recursive: true })
mkdirSync(join(fixture, 'build/native-deps/native'), { recursive: true })
writeFileSync(join(fixture, 'build/native-deps/node-pty/build/Release/pty.node'), 'synthetic PTY')
writeFileSync(join(fixture, 'build/native-deps/native/command-screenshot-monitor'), 'synthetic helper')
symlinkSync(join(source, 'apps/desktop/scripts'), join(fixture, 'scripts'))
execFileSync('bash', ['-e', nativeCopyPhaseFile], { cwd: fixture })
assert.equal(readFileSync(join(fixture, 'dist/node_modules/node-pty/build/Release/pty.node'), 'utf8'), 'synthetic PTY')
assert.ok(existsSync(join(fixture, 'dist/native/command-screenshot-monitor')), 'prepared native helper must be copied into dist/native')
assert.equal(readFileSync(join(fixture, 'dist/native/command-screenshot-monitor'), 'utf8'), 'synthetic helper')
assert.ok(!existsSync(join(fixture, 'dist/node_modules/native')), 'helper namespace must not be nested under node_modules')
console.log('PASS actual-production-native-copy synthetic modules/helper layout')
console.log(`PASS actual-electron-stamp ${version} ${revision}`)
