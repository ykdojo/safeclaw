const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');

// SSE clients
const sseClients = new Set();

// Watch Docker events for safeclaw containers
let dockerEvents;
function startDockerEvents() {
    dockerEvents = spawn('docker', ['events', '--filter', 'name=safeclaw', '--format', '{{.Action}}']);
    dockerEvents.stdout.on('data', (data) => {
        const action = data.toString().trim();
        if (['start', 'stop', 'die', 'destroy'].includes(action)) {
            // Notify all SSE clients
            sseClients.forEach(res => {
                res.write(`data: ${action}\n\n`);
            });
        }
    });
    dockerEvents.on('error', () => {});
    dockerEvents.on('close', () => {
        // Restart if it dies
        setTimeout(startDockerEvents, 1000);
    });
}
startDockerEvents();

const PORT = 7680;
const TEMPLATE_PATH = path.join(__dirname, 'template.html');

function getSessions() {
    const sessions = [];

    // Get all safeclaw containers (running and stopped)
    try {
        const output = execSync(
            `docker ps -a --format '{{.Names}}\\t{{.Status}}' --filter 'name=safeclaw'`,
            { encoding: 'utf8' }
        );

        output.trim().split('\n').filter(Boolean).forEach(line => {
            const [name, status] = line.split('\t');
            const isRunning = status.startsWith('Up');

            let port = null;
            let volume = '-';

            if (isRunning) {
                // Get port for running containers
                try {
                    const portOutput = execSync(
                        `docker ps --format '{{.Ports}}' --filter 'name=^${name}$'`,
                        { encoding: 'utf8' }
                    ).trim();
                    const portMatch = portOutput.match(/:(\d+)->7681/);
                    port = portMatch ? portMatch[1] : null;
                } catch (e) {}
            }

            // Get volume mount (exclude internal projects mount)
            try {
                const inspect = execSync(
                    `docker inspect ${name} --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}\n{{end}}{{end}}'`,
                    { encoding: 'utf8' }
                ).trim();
                const mounts = inspect.split('\n').filter(m =>
                    m && !m.endsWith(':/home/sclaw/.claude/projects')
                );
                volume = mounts.join(', ') || '-';
            } catch (e) {}

            sessions.push({
                name,
                port,
                url: port ? `http://localhost:${port}` : null,
                volume,
                active: isRunning
            });
        });
    } catch (e) {}

    // Sort: active first, then by name
    sessions.sort((a, b) => {
        if (a.active !== b.active) return b.active - a.active;
        return a.name.localeCompare(b.name);
    });

    return sessions;
}

function stopContainer(name) {
    try {
        execSync(`docker stop -t 1 ${name}`, { encoding: 'utf8' });
        return true;
    } catch (e) {
        return false;
    }
}

function deleteContainer(name) {
    try {
        execSync(`docker rm ${name}`, { encoding: 'utf8' });
        return true;
    } catch (e) {
        return false;
    }
}

function createContainer(options) {
    try {
        const scriptPath = path.join(__dirname, '..', 'scripts', 'new.sh');
        let args = '-n'; // always skip browser open (we handle it in frontend)

        if (options.name) {
            args += ` -s ${options.name}`;
        }
        if (options.volume) {
            args += ` -v ${options.volume}`;
        }
        if (options.query) {
            // Escape quotes in the query
            const escapedQuery = options.query.replace(/"/g, '\\"');
            args += ` -q "${escapedQuery}"`;
        }

        const output = execSync(`${scriptPath} ${args}`, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] });

        // Extract URL from output
        const urlMatch = output.match(/http:\/\/localhost:\d+/);
        const url = urlMatch ? urlMatch[0] : null;

        return { success: true, url };
    } catch (e) {
        // execSync error has stderr as Buffer
        let error = 'Failed to create session';
        if (e.stderr && e.stderr.length > 0) {
            error = e.stderr.toString().trim();
        } else if (e.message) {
            error = e.message;
        }
        return { success: false, error };
    }
}

function startContainer(name) {
    try {
        execSync(`docker start ${name}`, { encoding: 'utf8' });
        // Start ttyd inside the container
        const secretsDir = process.env.HOME + '/.config/safeclaw/.secrets';
        let envFlags = '';
        try {
            const files = fs.readdirSync(secretsDir);
            files.forEach(f => {
                const val = fs.readFileSync(`${secretsDir}/${f}`, 'utf8').trim();
                envFlags += ` -e ${f}=${val}`;
            });
        } catch (e) {}

        const sessionName = name.replace('safeclaw-', '').replace('safeclaw', 'default');
        const title = name === 'safeclaw' ? 'SafeClaw' : `SafeClaw - ${sessionName}`;
        execSync(`docker exec ${envFlags} -d ${name} ttyd -W -t titleFixed="${title}" -p 7681 /home/sclaw/ttyd-wrapper.sh`, { encoding: 'utf8' });

        // Get the port
        const portInfo = execSync(`docker ps --filter "name=^${name}$" --format "{{.Ports}}"`, { encoding: 'utf8' }).trim();
        const portMatch = portInfo.match(/:(\d+)->/);
        const port = portMatch ? portMatch[1] : '7681';

        return { success: true, url: `http://localhost:${port}` };
    } catch (e) {
        return { success: false };
    }
}

function renderContent(sessions) {
    if (sessions.length === 0) {
        return `<div class="empty">
            <p>no sessions</p>
            <table class="help">
                <tr><td><code>./scripts/run.sh</code></td><td>default session</td></tr>
                <tr><td><code>./scripts/run.sh -s name</code></td><td>named session</td></tr>
                <tr><td><code>./scripts/run.sh -n</code></td><td>skip opening browser</td></tr>
                <tr><td><code>./scripts/run.sh -v ~/p:/home/sclaw/p</code></td><td>mount volume</td></tr>
                <tr><td><code>./scripts/run.sh -q "question"</code></td><td>start with query</td></tr>
            </table>
            <p class="tip">tip: ${['in a session, press q or scroll to the bottom to exit scroll mode and resume typing', 'on this dashboard, press tab and enter to quickly create a new session'][Math.floor(Math.random() * 2)]}</p>
        </div>`;
    }

    const sessionRows = sessions.map(s => {
        const displayName = s.name.replace('safeclaw-', '').replace('safeclaw', 'default');
        const displayUrl = s.url ? s.url.replace('http://', '') : '';
        const urlCell = s.active
            ? `<a href="${s.url}" target="_blank">${displayUrl}</a>`
            : `<button class="start-btn" onclick="startSession('${s.name}')">start</button>`;
        const actionBtn = s.active
            ? `<button class="stop-btn" onclick="stopSession('${s.name}', this)">stop</button>`
            : `<button class="delete-btn" onclick="deleteSession('${s.name}', this)">delete</button>`;

        return `
        <tr class="${s.active ? '' : 'inactive-row'}" data-name="${s.name}" data-url="${s.url || ''}">
            <td><a href="#" class="session-name" onclick="showSessionInfo('${s.name}'); return false;">${displayName}</a></td>
            <td>${urlCell}</td>
            <td class="volume">${s.volume || '-'}</td>
            <td>${actionBtn}</td>
        </tr>
        `;
    }).join('');

    const activeSessions = sessions.filter(s => s.active);
    const iframes = activeSessions.map(s => `
        <div class="frame" id="frame-${s.name}">
            <div class="frame-bar">
                <span>${s.name.replace('safeclaw-', '').replace('safeclaw', 'default')}</span>
                <div class="frame-actions">
                    <a href="#" class="frame-stop" onclick="stopSessionLink('${s.name}', this); return false;">stop</a>
                    <a href="#" onclick="document.querySelector('#frame-${s.name} iframe').src='${s.url}'; return false;">refresh</a>
                    <a href="${s.url}" target="_blank">open</a>
                </div>
            </div>
            <iframe src="${s.url}"></iframe>
        </div>
    `).join('');

    return `
    <div class="table-wrapper">
        <table class="sessions">
            <thead><tr><th>Session</th><th>URL</th><th>Volume</th><th></th></tr></thead>
            <tbody>${sessionRows}</tbody>
        </table>
    </div>
    ${activeSessions.length > 0 ? `<div class="frames${activeSessions.length === 1 ? ' single' : ''}">${iframes}</div>` : ''}
    `;
}

const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://localhost:${PORT}`);

    if (url.pathname === '/api/sessions') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(getSessions()));
    } else if (url.pathname === '/api/stop' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const { name } = JSON.parse(body);
            const success = stopContainer(name);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success }));
        });
    } else if (url.pathname === '/api/delete' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const { name } = JSON.parse(body);
            const success = deleteContainer(name);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success }));
        });
    } else if (url.pathname === '/api/start' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const { name } = JSON.parse(body);
            const result = startContainer(name);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(result));
        });
    } else if (url.pathname === '/api/create' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            const options = JSON.parse(body);
            const result = createContainer(options);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(result));
        });
    } else if (url.pathname === '/api/events') {
        // Server-Sent Events for real-time updates
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive'
        });
        res.write('data: connected\n\n');
        sseClients.add(res);
        req.on('close', () => sseClients.delete(res));
    } else {
        const template = fs.readFileSync(TEMPLATE_PATH, 'utf8');
        const content = renderContent(getSessions());
        const html = template.replace('{{CONTENT}}', content);
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(html);
    }
});

server.listen(PORT, '127.0.0.1', () => {
    const url = `http://localhost:${PORT}`;
    console.log(url);

    // Open in browser
    const { exec } = require('child_process');
    const cmd = process.platform === 'darwin' ? 'open' : 'xdg-open';
    exec(`${cmd} ${url}`);
});
