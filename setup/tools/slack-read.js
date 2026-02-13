#!/usr/bin/env node

// Slack Read-Only Tool
// Usage: node slack-read.js <command> [args]

const { WebClient } = require('@slack/web-api');

// Get token from env var
function getToken(envVarName = 'SLACK_TOKEN') {
    const token = process.env[envVarName];
    if (!token) {
        console.error(`${envVarName} env var not set.`);
        console.error('Run: ./scripts/setup-slack.sh');
        process.exit(1);
    }
    return token;
}

// Parse --token flag
let tokenEnvVar = 'SLACK_TOKEN';
const rawArgs = process.argv.slice(2);
const tokenFlagIdx = rawArgs.indexOf('--token');
if (tokenFlagIdx !== -1) {
    tokenEnvVar = rawArgs[tokenFlagIdx + 1];
    if (!tokenEnvVar) {
        console.error('--token requires an env var name');
        process.exit(1);
    }
    rawArgs.splice(tokenFlagIdx, 2);
}

const client = new WebClient(getToken(tokenEnvVar));

// Commands
const commands = {
    async channels() {
        const result = await client.conversations.list({ types: 'public_channel,private_channel' });
        for (const ch of result.channels) {
            const type = ch.is_private ? 'private' : 'public';
            console.log(`${ch.id}\t${ch.name}\t(${type})`);
        }
    },

    async dms() {
        const result = await client.conversations.list({ types: 'im,mpim' });
        for (const ch of result.channels) {
            const type = ch.is_mpim ? 'group-dm' : 'dm';
            console.log(`${ch.id}\t${ch.name || ch.user || 'unnamed'}\t(${type})`);
        }
    },

    async history(channelId, limit = 20) {
        if (!channelId) {
            console.error('Usage: slack-read.js history <channel_id> [limit]');
            process.exit(1);
        }
        const result = await client.conversations.history({
            channel: channelId,
            limit: parseInt(limit)
        });
        for (const msg of result.messages.reverse()) {
            const time = new Date(msg.ts * 1000).toISOString();
            const user = msg.user || 'unknown';
            console.log(`[${time}] ${user}: ${msg.text}`);
        }
    },

    async search(query, limit = 20) {
        if (!query) {
            console.error('Usage: slack-read.js search <query> [limit]');
            process.exit(1);
        }
        const result = await client.search.messages({
            query,
            count: parseInt(limit)
        });
        for (const match of result.messages.matches) {
            const time = new Date(match.ts * 1000).toISOString();
            const user = match.user || match.username || 'unknown';
            const channel = match.channel?.name || 'unknown';
            console.log(`[${time}] #${channel} ${user}: ${match.text}`);
            console.log('---');
        }
    },

    async users() {
        const result = await client.users.list();
        for (const user of result.members) {
            if (!user.deleted && !user.is_bot) {
                console.log(`${user.id}\t${user.name}\t${user.real_name || ''}`);
            }
        }
    },

    async info(channelId) {
        if (!channelId) {
            console.error('Usage: slack-read.js info <channel_id>');
            process.exit(1);
        }
        const result = await client.conversations.info({ channel: channelId });
        const ch = result.channel;
        console.log(`Name: ${ch.name}`);
        console.log(`ID: ${ch.id}`);
        console.log(`Type: ${ch.is_private ? 'private' : 'public'}`);
        console.log(`Members: ${ch.num_members || 'unknown'}`);
        console.log(`Topic: ${ch.topic?.value || 'none'}`);
        console.log(`Purpose: ${ch.purpose?.value || 'none'}`);
    },

    help() {
        console.log(`Slack Read-Only Tool

Usage: slack-read.js [--token ENV_VAR] <command> [args]

Options:
  --token ENV_VAR       Use a different env var (default: SLACK_TOKEN)

Commands:
  channels              List all channels (public & private)
  dms                   List DMs and group DMs
  history <id> [n]      Read last n messages from channel (default: 20)
  search <query> [n]    Search messages (default: 20 results)
  users                 List workspace users
  info <id>             Get channel info
  help                  Show this help
`);
    }
};

// Main
async function main() {
    const [command, ...args] = rawArgs;

    if (!command || !commands[command]) {
        commands.help();
        process.exit(command ? 1 : 0);
    }

    try {
        await commands[command](...args);
    } catch (err) {
        console.error('Error:', err.message);
        process.exit(1);
    }
}

main();
