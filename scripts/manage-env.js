#!/usr/bin/env node
// Manage SafeClaw environment variables

const fs = require('fs');
const path = require('path');
const { select, input, password, confirm } = require('@inquirer/prompts');

const SECRETS_DIR = path.join(
  process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config'),
  'safeclaw',
  '.secrets'
);

function getKeys() {
  if (!fs.existsSync(SECRETS_DIR)) return [];
  return fs.readdirSync(SECRETS_DIR).filter(f => {
    const stat = fs.statSync(path.join(SECRETS_DIR, f));
    return stat.isFile();
  });
}

async function manageKeys() {
  const keys = getKeys();

  if (keys.length === 0) {
    console.log('\nNo keys found.\n');
    return;
  }

  const choices = [
    ...keys.map(key => ({ name: key, value: key })),
    { name: '← Back', value: 'back' }
  ];

  console.log(`\nKeys from ${SECRETS_DIR}/\n`);

  const keyToDelete = await select({
    message: 'Select key to delete:',
    choices
  });

  if (keyToDelete === 'back') {
    return;
  }

  const confirmed = await confirm({
    message: `Delete ${keyToDelete}?`,
    default: false
  });

  if (confirmed) {
    fs.unlinkSync(path.join(SECRETS_DIR, keyToDelete));
    console.log(`\nDeleted ${keyToDelete}\n`);
  } else {
    console.log('\nCancelled.\n');
  }
}

async function addKey() {
  console.log('\nExample: OPENAI_API_KEY\n');

  const name = await input({
    message: 'Name:',
    validate: val => {
      if (!val) return 'Name is required';
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(val)) {
        return 'Use letters, numbers, and underscores only';
      }
      return true;
    }
  });

  const value = await password({
    message: 'Value:',
    mask: '*',
    validate: val => val ? true : 'Value is required'
  });

  fs.mkdirSync(SECRETS_DIR, { recursive: true, mode: 0o700 });
  const filePath = path.join(SECRETS_DIR, name);
  fs.writeFileSync(filePath, value, { mode: 0o600 });

  console.log(`\nSaved to ${filePath}`);
  console.log('Restart SafeClaw to use: ./scripts/run.sh\n');
}

async function mainMenu() {
  while (true) {
    const action = await select({
      message: 'What would you like to do?',
      choices: [
        { name: 'Manage keys', value: 'manage' },
        { name: 'Add key', value: 'add' },
        { name: 'Exit', value: 'exit' }
      ]
    });

    switch (action) {
      case 'manage':
        await manageKeys();
        break;
      case 'add':
        await addKey();
        break;
      case 'exit':
        return;
    }
  }
}

mainMenu().catch(err => {
  console.error(err);
  process.exit(1);
});
