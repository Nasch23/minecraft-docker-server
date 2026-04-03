import { Elysia } from 'elysia'
import { staticPlugin } from '@elysiajs/static'

const ANSI_REGEX = /\x1b\[[0-9;]*[mGKHFJA-Z]/g
const stripAnsi = (str: string) => str.replace(ANSI_REGEX, '')

let wsIdCounter = 0
const logProcs = new Map<number, ReturnType<typeof Bun.spawn>>()
const wsClients = new Set<any>()

function broadcast(msg: string) {
  for (const ws of wsClients) {
    try { ws.send(msg) } catch {}
  }
}

const app = new Elysia()
  .use(staticPlugin({ assets: 'public', prefix: '/' }))

  .get('/api/status', async () => {
    try {
      const proc = Bun.spawn(
        ['docker', 'inspect', '-f', '{{.State.Running}}', 'mc-serveur'],
        { stdout: 'pipe', stderr: 'pipe' }
      )
      await proc.exited
      const text = await new Response(proc.stdout).text()
      return { running: text.trim() === 'true' }
    } catch {
      return { running: false }
    }
  })

  .post('/api/start', async () => {
    const proc = Bun.spawn(['docker', 'start', 'mc-serveur'], {
      stdout: 'pipe',
      stderr: 'pipe',
    })
    await proc.exited
    return { success: proc.exitCode === 0 }
  })

  .post('/api/stop', async () => {
    try {
      await Bun.spawn(['docker', 'exec', 'mc-serveur', 'rcon-cli', 'save-all'], {
        stdout: 'pipe',
        stderr: 'pipe',
      }).exited
    } catch {}

    const proc = Bun.spawn(['docker', 'stop', 'mc-serveur'], {
      stdout: 'pipe',
      stderr: 'pipe',
    })
    await proc.exited

    // Push de la save sur GitHub
    const gitToken = process.env.GITHUB_TOKEN
    const gitRepoUrl = process.env.GIT_REPO_URL
    if (gitToken && gitRepoUrl) {
      broadcast('[dashboard] Sauvegarde GitHub en cours...')
      try {
        const gitEnv = {
          ...process.env,
          GIT_AUTHOR_NAME: 'MC Server',
          GIT_AUTHOR_EMAIL: 'mc@server.local',
          GIT_COMMITTER_NAME: 'MC Server',
          GIT_COMMITTER_EMAIL: 'mc@server.local',
          GIT_TERMINAL_PROMPT: '0',
          GIT_ASKPASS: 'echo',
        }
        const repoWithToken = gitRepoUrl.replace('https://', `https://${gitToken}@`)
        await Bun.spawn(['git', '-C', '/project', 'remote', 'set-url', 'origin', repoWithToken],
          { stdout: 'ignore', stderr: 'ignore', env: gitEnv }).exited
        broadcast('[dashboard] git add...')
        await Bun.spawn(['git', '-C', '/project', 'add', 'data/'],
          { stdout: 'ignore', stderr: 'ignore', env: gitEnv }).exited
        broadcast('[dashboard] git commit...')
        await Bun.spawn(['git', '-C', '/project', 'commit', '-m', `Save: ${new Date().toISOString()}`],
          { stdout: 'ignore', stderr: 'ignore', env: gitEnv }).exited
        broadcast('[dashboard] git pull --rebase...')
        await Bun.spawn(['git', '-C', '/project', 'pull', '--rebase'],
          { stdout: 'ignore', stderr: 'ignore', env: gitEnv }).exited
        broadcast('[dashboard] git push...')
        const push = Bun.spawn(['git', '-C', '/project', 'push'],
          { stdout: 'ignore', stderr: 'ignore', env: gitEnv })
        await push.exited
        if (push.exitCode !== 0) {
          broadcast('[dashboard] git push --force...')
          await Bun.spawn(['git', '-C', '/project', 'push', '--force'],
            { stdout: 'ignore', stderr: 'ignore', env: gitEnv }).exited
        }
        broadcast('[dashboard] Sauvegarde poussée sur GitHub ✓')
      } catch (e: any) {
        broadcast(`[dashboard] Erreur sauvegarde GitHub: ${e?.message ?? e}`)
      }
    }

    // Reset du statut sur le Gist
    const token = process.env.GITHUB_TOKEN
    const gistId = process.env.GIST_ID
    if (token && gistId) {
      try {
        await fetch(`https://api.github.com/gists/${gistId}`, {
          method: 'PATCH',
          headers: {
            Authorization: `token ${token}`,
            'User-Agent': 'MC-Dashboard',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            files: {
              'mc-status.json': {
                content: JSON.stringify({ running: false, host: '', since: '' }),
              },
            },
          }),
        })
      } catch {}
    }

    return { success: proc.exitCode === 0 }
  })

  .post('/api/console', async ({ body }) => {
    const { command } = body as { command: string }
    if (!command?.trim()) return { output: '' }

    const proc = Bun.spawn(
      ['docker', 'exec', 'mc-serveur', 'rcon-cli', ...command.trim().split(' ')],
      { stdout: 'pipe', stderr: 'pipe' }
    )
    await proc.exited
    const output = await new Response(proc.stdout).text()
    const err = await new Response(proc.stderr).text()
    return { output: (output || err).trim() }
  })

  .ws('/ws/logs', {
    open(ws) {
      wsClients.add(ws)
      const id = wsIdCounter++
      ;(ws as any)._wsId = id

      const proc = Bun.spawn(
        ['docker', 'logs', '-f', '--tail', '200', 'mc-serveur'],
        { stdout: 'pipe', stderr: 'pipe' }
      )
      logProcs.set(id, proc)

      const stream = async (readable: ReadableStream<Uint8Array>) => {
        const reader = readable.getReader()
        const decoder = new TextDecoder()
        try {
          while (true) {
            const { done, value } = await reader.read()
            if (done) break
            const text = stripAnsi(decoder.decode(value))
            if (text.trim()) {
              try {
                ws.send(text)
              } catch {}
            }
          }
        } catch {}
      }

      stream(proc.stdout)
      stream(proc.stderr)
    },
    close(ws) {
      wsClients.delete(ws)
      const id = (ws as any)._wsId
      if (id !== undefined) {
        logProcs.get(id)?.kill()
        logProcs.delete(id)
      }
    },
  })

  .listen(3000, () => {
    console.log('Dashboard disponible sur http://localhost:3000')
  })
