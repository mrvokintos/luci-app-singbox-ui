'use strict';

const assert = require('node:assert/strict');

function cleanError(s) {
	return String(s ?? '').replace(/\x1b\[[0-9;]*m/g, '').trim();
}

function parseBinaryVersion(stdout, stderr, code) {
	if ((code | 0) !== 0 && !stdout) return 'sing-box —';
	const text = cleanError(stdout || stderr);
	const line = text.split(/\r?\n/).map(s => s.trim()).find(Boolean) || '';
	const match = line.match(/(?:^|\s)(?:sing-box(?:-extended)?\s+version\s+v?([0-9][\w.+-]*|unknown)|sing-box(?:-extended)?\s+v?([0-9][\w.+-]*)|version\s+v?([0-9][\w.+-]*|unknown))/i);
	const v = match && (match[1] || match[2] || match[3]);
	return v ? 'sing-box ' + v : 'sing-box —';
}

const cases = [
	{ out: 'sing-box version 1.10.7', err: '', code: 0, expected: 'sing-box 1.10.7' },
	{ out: 'sing-box version 1.12.17-extended-1.5.2\n', err: '', code: 0, expected: 'sing-box 1.12.17-extended-1.5.2' },
	{ out: '\n\nsing-box version 1.11.0-alpha.5 (go1.22.5 linux/amd64)\n', err: '', code: 0, expected: 'sing-box 1.11.0-alpha.5' },
	{ out: 'sing-box version 1.12.0-rc.1', err: '', code: 0, expected: 'sing-box 1.12.0-rc.1' },
	{ out: 'sing-box version unknown', err: '', code: 0, expected: 'sing-box unknown' },
	{ out: 'sing-box-extended version 1.12.17-extended-1.5.2', err: '', code: 0, expected: 'sing-box 1.12.17-extended-1.5.2' },
	{ out: 'sing-box-extended version unknown', err: '', code: 0, expected: 'sing-box unknown' },
	{ out: 'sing-box 1.10.7', err: '', code: 0, expected: 'sing-box 1.10.7' },
	{ out: 'sing-box v1.10.7', err: '', code: 0, expected: 'sing-box 1.10.7' },
	{ out: '', err: 'sing-box: not found', code: 127, expected: 'sing-box —' },
	{ out: '', err: '', code: 1, expected: 'sing-box —' },
	{ out: 'unknown command', err: '', code: 1, expected: 'sing-box —' },
	{ out: 'sing-box: command not found', err: '', code: 127, expected: 'sing-box —' },
	{ out: 'FATAL[0000] sing-box error', err: '', code: 1, expected: 'sing-box —' }
];

for (const c of cases) {
	const res = parseBinaryVersion(c.out, c.err, c.code);
	assert.equal(res, c.expected, `Failed for input: ${c.out || c.err}`);
}

console.log('version parser: ' + cases.length + ' test cases passed');
