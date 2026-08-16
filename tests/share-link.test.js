'use strict';

const assert = require('node:assert/strict');
const { parseShareLink } = require('../luci-app-singbox-ui/htdocs/luci-static/resources/singbox-ui/share-link.js');

const uuid = '11111111-1111-1111-1111-111111111111';
const vmess = 'vmess://' + Buffer.from(JSON.stringify({
	ps: 'VMess node', add: 'vmess.example', port: 443, id: uuid, aid: 0,
	net: 'ws', host: 'cdn.example', path: '/ws', tls: 'tls', sni: 'vmess.example',
})).toString('base64');
const ss = 'ss://' + Buffer.from('aes-128-gcm:secret').toString('base64') +
	'@ss.example:8388?plugin=v2ray-plugin%3Bobfs%3Dweb#SS%20node';

const cases = [
	['vless://' + uuid + '@vless.example:443?security=reality&sni=sni.example&pbk=key&sid=01&fp=chrome&type=grpc&serviceName=grpc#VLESS', 'vless'],
	['trojan://secret@trojan.example:443?sni=trojan.example#Trojan', 'trojan'],
	['hy2://secret@hy2.example:443?sni=hy2.example&obfs=salamander&obfs-password=hide#Hy2', 'hysteria2'],
	['hysteria://secret@hy.example:443?upmbps=20&downmbps=100#Hysteria', 'hysteria'],
	['tuic://' + uuid + ':secret@tuic.example:443?sni=tuic.example#TUIC', 'tuic'],
	['socks5://user:pass@socks.example:1080#SOCKS', 'socks'],
	['https://user:pass@http.example:8443#HTTP', 'http'],
	[vmess, 'vmess'],
	[ss, 'shadowsocks'],
];

for (const [link, type] of cases) {
	const parsed = parseShareLink(link);
	assert.equal(parsed.outbound.type, type);
	assert.equal(parsed.outbound.tag, 'proxy');
	assert.ok(parsed.outbound.server);
	assert.ok(parsed.outbound.server_port > 0);
}

assert.equal(parseShareLink(cases[0][0]).outbound.tls.reality.public_key, 'key');
assert.equal(parseShareLink(cases[0][0]).outbound.tls.utls.fingerprint, 'chrome');
assert.equal(parseShareLink(ss).outbound.plugin, 'v2ray-plugin');
assert.equal(parseShareLink(ss).outbound.plugin_opts, 'obfs=web');
assert.throws(() => parseShareLink('ftp://example.com/file'), /Unsupported/);
console.log('share-link parser: ' + cases.length + ' protocols passed');
