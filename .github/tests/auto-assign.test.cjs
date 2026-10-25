const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

// Test the exact trusted workflow script, without GitHub writes or app XCTest.
const yaml = readFileSync(join(__dirname, '../workflows/auto-assign.yml'), 'utf8');
const script = yaml.split('          script: |\n')[1]
  .split('\n').map(line => line.replace(/^ {12}/, '')).join('\n');
const execute = new (Object.getPrototypeOf(async function () {}).constructor)(
  'github', 'context', 'core', script
);
const allLabels = ['💻 Feat', '🐞 Fix', '🎨 Style', '📘 Docs', '📄 Chore', '🔨 Refactor',
  '⚙️ CI', '🧪 Test', '➕ Add', '🔨 HotFix', '🚀 deploy', '데빈', '테오', '원', '린', 'custom'];

function fixture(options = {}) {
  const owner = 'example';
  const repo = 'labcord';
  const item = {
    number: 99, title: 'feat: implement', body: '',
    user: { login: 'hellosunghyun', type: 'User' }, assignees: [], labels: [],
    ...options.item
  };
  const writes = [];
  const reads = [];
  const warnings = [];
  const fail = status => { throw Object.assign(new Error('mock failure'), { status }); };
  const issues = {
    get: async ({ issue_number }) => {
      reads.push(issue_number);
      if (issue_number === item.number) return { data: item };
      const linked = options.linked?.[issue_number];
      if (!linked) return fail(404);
      return { data: { html_url: `https://github.com/${owner}/${repo}/issues/${issue_number}`, ...linked } };
    },
    listLabelsForRepo: () => {},
    addLabels: async args => {
      if (options.labelError) return fail(options.labelError);
      assert.equal(args.owner, owner);
      assert.equal(args.repo, repo);
      writes.push({ labels: args.labels });
      item.labels.push(...args.labels.map(name => ({ name })));
    },
    checkUserCanBeAssigned: async () => {
      if (options.ineligible) return fail(404);
      if (options.concurrentAssignee) item.assignees = [{ login: 'manual' }];
      return { status: 204 };
    },
    addAssignees: async args => {
      assert.equal(args.owner, owner);
      assert.equal(args.repo, repo);
      writes.push({ assignees: args.assignees });
      item.assignees.push(...args.assignees.map(login => ({ login })));
    }
  };
  const github = {
    rest: { issues },
    paginate: async () => (options.available ?? allLabels).map(name => ({ name }))
  };
  const context = {
    repo: { owner, repo },
    payload: options.pr ? { pull_request: { number: item.number, head: {
      ref: options.branch ?? 'feat/#22-Theo',
      repo: { full_name: options.headRepo ?? `${owner}/${repo}` }
    } } } : { issue: { number: item.number } }
  };
  return { item, writes, reads, warnings,
    run: () => execute(github, context, { warning: message => warnings.push(message), info: () => {} }) };
}

test('issue author and labels are added once across repeated runs', async () => {
  const f = fixture();
  await f.run(); await f.run();
  assert.deepEqual(f.writes, [{ labels: ['💻 Feat', '데빈'] }, { assignees: ['hellosunghyun'] }]);
});

test('existing assignees and labels survive', async () => {
  const f = fixture({ item: { assignees: [{ login: 'manual' }], labels: [{ name: 'custom' }] } });
  await f.run();
  assert.deepEqual(f.item.assignees, [{ login: 'manual' }]);
  assert.ok(f.item.labels.some(label => label.name === 'custom'));
  assert.equal(f.writes.length, 1);
});

for (const user of [{ login: 'robot', type: 'Bot' }, { login: 'robot[bot]', type: 'User' }]) {
  test(`bot ${user.login} is excluded`, async () => {
    const f = fixture({ item: { user } }); await f.run(); assert.deepEqual(f.writes, []);
  });
}

test('unknown account, title and missing labels do not create labels', async () => {
  const f = fixture({ available: [], item: { title: 'build: assets', user: { login: 'unknown' } } });
  await f.run(); assert.deepEqual(f.writes, [{ assignees: ['unknown'] }]);
  const missing = fixture({ available: [] }); await missing.run();
  assert.equal(missing.writes.length, 1); assert.equal(missing.warnings.length, 1);
});

for (const body of ['Closes #22', 'FIXES: example/labcord#22',
  'Resolves https://github.com/example/labcord/issues/22']) {
  test(`same-repo issue inherits labels with category priority: ${body}`, async () => {
    const f = fixture({ pr: true, item: { body, labels: [{ name: '💻 Feat' }] }, linked: {
      22: { labels: [{ name: '📘 Docs' }, { name: '원' }, { name: 'custom' }] }
    } });
    await f.run(); await f.run();
    assert.deepEqual(f.writes, [{ labels: ['📘 Docs', '원', 'custom'] }, { assignees: ['hellosunghyun'] }]);
    assert.ok(f.item.labels.some(label => label.name === '💻 Feat'));
  });
}

test('branch issue fallback and multiple explicit references', async () => {
  const f = fixture({ pr: true, linked: { 22: { labels: [{ name: '🐞 Fix' }] } } });
  await f.run(); assert.deepEqual(f.writes[0], { labels: ['🐞 Fix', '데빈'] });
  const multi = fixture({ pr: true, item: { body: 'Closes #22, fixes #23, fixes #22' }, linked: {
    22: { labels: [{ name: 'custom' }] }, 23: { labels: [{ name: '원' }] }
  } });
  await multi.run(); assert.equal(multi.reads.filter(number => number === 22).length, 1);
  assert.deepEqual(multi.writes[0], { labels: ['custom', '원', '💻 Feat'] });
});

for (const body of ['Closes other/repo#22', 'Closes https://github.com/other/repo/issues/22',
  'Closes https://evil.example/example/labcord/issues/22', 'mentions #22']) {
  test(`foreign/non-link reference is not fetched: ${body}`, async () => {
    const f = fixture({ pr: true, branch: 'docs/no-issue', item: { body } });
    await f.run(); assert.ok(!f.reads.includes(22));
  });
}

test('foreign fork branch numbers are not treated as local issues', async () => {
  const f = fixture({ pr: true, headRepo: 'foreign/fork' });
  await f.run(); assert.ok(!f.reads.includes(22));
});

for (const linked of [undefined, { pull_request: {}, labels: [{ name: '📘 Docs' }] },
  { html_url: 'https://github.com/other/repo/issues/22', labels: [{ name: '📘 Docs' }] }]) {
  test(`missing, PR or moved issue falls back to own metadata: ${JSON.stringify(linked)}`, async () => {
    const f = fixture({ pr: true, linked: { 22: linked } });
    await f.run(); assert.deepEqual(f.writes[0], { labels: ['💻 Feat', '데빈'] });
  });
}

test('unassignable author and concurrent manual assignment are preserved', async () => {
  for (const option of [{ ineligible: true }, { concurrentAssignee: true }]) {
    const f = fixture(option); await f.run(); assert.equal(f.writes.length, 1);
  }
});

test('permission error is logged and independent assignment proceeds', async () => {
  const f = fixture({ labelError: 403 }); await f.run();
  assert.equal(f.warnings.length, 1);
  assert.deepEqual(f.writes, [{ assignees: ['hellosunghyun'] }]);
});

test('unexpected service error fails visibly', async () => {
  const f = fixture({ labelError: 500 }); await assert.rejects(f.run(), /mock failure/);
});

test('PR title convention and confirmed team mappings', async () => {
  for (const [login, label] of [['junghongseop', '테오'], ['wondrone0113', '원']]) {
    const f = fixture({ pr: true, branch: 'docs/no-issue', item: {
      title: 'docs/#31: title', user: { login }
    } });
    await f.run(); assert.deepEqual(f.writes[0], { labels: ['📘 Docs', label] });
  }
});
