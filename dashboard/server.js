const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = 7680;
const TEMPLATE_PATH = path.join(__dirname, 'template.html');

function getSessions() {
    try {
        const output = execSync(
            `docker ps --format '{{.Names}}\\t{{.Ports}}\\t{{.Mounts}}' --filter 'name=safeclaw'`,
            { encoding: 'utf8' }
        );

        return output.trim().split('\n').filter(Boolean).map(line => {
            const [name, ports, mounts] = line.split('\t');
            const portMatch = ports.match(/:(\d+)->7681/);
            const port = portMatch ? portMatch[1] : null;

            let volume = '';
            try {
                const inspect = execSync(
                    `docker inspect ${name} --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{end}}{{end}}'`,
                    { encoding: 'utf8' }
                ).trim();
                volume = inspect || '-';
            } catch (e) {
                volume = '-';
            }

            return { name, port, url: port ? `http://localhost:${port}` : null, volume };
        }).filter(s => s.port);
    } catch (e) {
        return [];
    }
}

function renderContent(sessions) {
    if (sessions.length === 0) {
        return '<p class="empty">no sessions running<br><br>./scripts/run.sh -s name</p>';
    }

    const sessionRows = sessions.map(s => `
        <tr>
            <td>${s.name.replace('safeclaw-', '').replace('safeclaw', 'default')}</td>
            <td><a href="${s.url}" target="_blank">${s.url}</a></td>
            <td class="volume">${s.volume || '-'}</td>
        </tr>
    `).join('');

    const iframes = sessions.map(s => `
        <div class="frame">
            <div class="frame-bar">
                <span>${s.name.replace('safeclaw-', '').replace('safeclaw', 'default')}</span>
                <a href="${s.url}" target="_blank">open</a>
            </div>
            <iframe src="${s.url}"></iframe>
        </div>
    `).join('');

    return `
    <table>
        <thead><tr><th>Session</th><th>URL</th><th>Volume</th></tr></thead>
        <tbody>${sessionRows}</tbody>
    </table>
    <div class="frames">${iframes}</div>
    `;
}

const server = http.createServer((req, res) => {
    if (req.url === '/api/sessions') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(getSessions()));
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
