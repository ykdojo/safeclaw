const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

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

            // Get volume mount
            try {
                const inspect = execSync(
                    `docker inspect ${name} --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{end}}{{end}}'`,
                    { encoding: 'utf8' }
                ).trim();
                volume = inspect || '-';
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

function startContainer(name) {
    try {
        execSync(`docker start ${name}`, { encoding: 'utf8' });
        // Start ttyd inside the container
        const secretsDir = process.env.HOME + '/.config/safeclaw/.secrets';
        let envFlags = '';
        try {
            const fs = require('fs');
            const files = fs.readdirSync(secretsDir);
            files.forEach(f => {
                const val = fs.readFileSync(`${secretsDir}/${f}`, 'utf8').trim();
                envFlags += ` -e ${f}=${val}`;
            });
        } catch (e) {}

        const sessionName = name.replace('safeclaw-', '').replace('safeclaw', 'default');
        const title = name === 'safeclaw' ? 'SafeClaw' : `SafeClaw - ${sessionName}`;
        execSync(`docker exec ${envFlags} -d ${name} ttyd -W -t titleFixed="${title}" -p 7681 /home/sclaw/ttyd-wrapper.sh`, { encoding: 'utf8' });
        return true;
    } catch (e) {
        return false;
    }
}

function renderContent(sessions) {
    if (sessions.length === 0) {
        return '<p class="empty">no sessions<br><br>./scripts/run.sh -s name</p>';
    }

    const sessionRows = sessions.map(s => {
        const displayName = s.name.replace('safeclaw-', '').replace('safeclaw', 'default');
        const urlCell = s.active
            ? `<a href="${s.url}" target="_blank">${s.url}</a>`
            : `<button class="start-btn" onclick="startSession('${s.name}')">start</button>`;
        const actionBtn = s.active
            ? `<button class="stop-btn" onclick="stopSession('${s.name}')">stop</button>`
            : `<button class="delete-btn" onclick="deleteSession('${s.name}')">delete</button>`;

        return `
        <tr class="${s.active ? '' : 'inactive-row'}">
            <td>${displayName}</td>
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
                <a href="${s.url}" target="_blank">open</a>
            </div>
            <iframe src="${s.url}"></iframe>
        </div>
    `).join('');

    return `
    <table>
        <thead><tr><th>Session</th><th>URL</th><th>Volume</th><th></th></tr></thead>
        <tbody>${sessionRows}</tbody>
    </table>
    ${activeSessions.length > 0 ? `<div class="frames">${iframes}</div>` : ''}
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
            const success = startContainer(name);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success }));
        });
    } else {
        const template = fs.readFileSync(TEMPLATE_PATH, 'utf8');
        const content = renderContent(getSessions());
        const html = template.replace('{{CONTENT}}', content);
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end(html);
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`http://localhost:${PORT}`);
});
