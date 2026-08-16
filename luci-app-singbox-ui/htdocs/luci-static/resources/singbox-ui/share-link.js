'use strict';
'require baseclass';

function decode(value) {
	try { return decodeURIComponent(value || ''); }
	catch (_) { return value || ''; }
}

function decodeBase64(value) {
	let normalized = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
	normalized += '='.repeat((4 - normalized.length % 4) % 4);
	if (typeof atob === 'function')
		return decodeURIComponent(Array.prototype.map.call(atob(normalized), c =>
			'%' + c.charCodeAt(0).toString(16).padStart(2, '0')).join(''));
	if (typeof Buffer !== 'undefined')
		return Buffer.from(normalized, 'base64').toString('utf8');
	throw new Error('Base64 decoder is unavailable');
}

function boolParam(params, name, fallback) {
	const value = params.get(name);
	if (value == null) return !!fallback;
	return /^(1|true|yes)$/i.test(value);
}

function numberParam(params, ...names) {
	for (const name of names) {
		const value = Number(params.get(name));
		if (Number.isFinite(value) && value > 0) return value;
	}
	return undefined;
}

function clean(object) {
	if (Array.isArray(object)) return object.map(clean);
	if (!object || typeof object !== 'object') return object;
	Object.keys(object).forEach(key => {
		const value = object[key];
		if (value === undefined || value === null || value === '' ||
		    (Array.isArray(value) && value.length === 0) ||
		    (typeof value === 'object' && !Array.isArray(value) && Object.keys(clean(value)).length === 0))
			delete object[key];
		else
			object[key] = clean(value);
	});
	return object;
}

function hostname(url) {
	return url.hostname.replace(/^\[|\]$/g, '');
}

function tagFrom(url, fallback) {
	return decode((url.hash || '').replace(/^#/, '')).trim() || fallback;
}

function tlsFrom(url, enabledByDefault) {
	const p = url.searchParams;
	const security = (p.get('security') || '').toLowerCase();
	const enabled = enabledByDefault || security === 'tls' || security === 'reality' || boolParam(p, 'tls', false);
	if (!enabled) return undefined;
	const tls = {
		enabled: true,
		server_name: p.get('sni') || p.get('peer') || p.get('serverName') || hostname(url),
		insecure: boolParam(p, 'allowInsecure', boolParam(p, 'insecure', false)),
		alpn: (p.get('alpn') || '').split(',').map(v => v.trim()).filter(Boolean),
		utls: p.get('fp') ? { enabled: true, fingerprint: p.get('fp') } : undefined,
	};
	if (security === 'reality' || p.get('pbk') || p.get('public-key')) {
		tls.reality = {
			enabled: true,
			public_key: p.get('pbk') || p.get('public-key'),
			short_id: p.get('sid') || p.get('short-id'),
		};
	}
	return clean(tls);
}

function transportFrom(url) {
	const p = url.searchParams;
	const type = (p.get('type') || p.get('network') || '').toLowerCase();
	if (!type || type === 'tcp' || type === 'raw') return undefined;
	if (type === 'ws') return clean({
		type: 'ws',
		path: p.get('path') || '/',
		headers: { Host: p.get('host') || undefined },
	});
	if (type === 'http' || type === 'h2') return clean({
		type: 'http',
		host: (p.get('host') || '').split(',').filter(Boolean),
		path: p.get('path') || '/',
	});
	if (type === 'grpc') return clean({
		type: 'grpc',
		service_name: p.get('serviceName') || p.get('service_name') || p.get('path'),
	});
	if (type === 'httpupgrade') return clean({
		type: 'httpupgrade',
		path: p.get('path') || '/',
		host: p.get('host'),
	});
	if (type === 'quic') return { type: 'quic' };
	return undefined;
}

function parseVless(url) {
	return clean({
		type: 'vless', tag: 'proxy', server: hostname(url), server_port: Number(url.port || 443),
		uuid: decode(url.username), flow: url.searchParams.get('flow'),
		packet_encoding: url.searchParams.get('packetEncoding') || url.searchParams.get('packet_encoding'),
		tls: tlsFrom(url, false), transport: transportFrom(url),
	});
}

function parseTrojan(url) {
	return clean({
		type: 'trojan', tag: 'proxy', server: hostname(url), server_port: Number(url.port || 443),
		password: decode(url.username || url.password), tls: tlsFrom(url, true), transport: transportFrom(url),
	});
}

function parseHysteria2(url) {
	const p = url.searchParams;
	return clean({
		type: 'hysteria2', tag: 'proxy', server: hostname(url), server_port: Number(url.port || 443),
		password: decode(url.username || url.password),
		up_mbps: numberParam(p, 'upmbps', 'up'), down_mbps: numberParam(p, 'downmbps', 'down'),
		obfs: (p.get('obfs') || p.get('obfs-password')) ? {
			type: p.get('obfs') || 'salamander', password: p.get('obfs-password') || p.get('obfsPassword'),
		} : undefined,
		tls: tlsFrom(url, true),
	});
}

function parseHysteria(url) {
	const p = url.searchParams;
	return clean({
		type: 'hysteria', tag: 'proxy', server: hostname(url), server_port: Number(url.port || 443),
		auth_str: decode(url.username || p.get('auth')), protocol: p.get('protocol'),
		up_mbps: numberParam(p, 'upmbps', 'up'), down_mbps: numberParam(p, 'downmbps', 'down'),
		obfs: p.get('obfs'), tls: tlsFrom(url, true),
	});
}

function parseTuic(url) {
	const p = url.searchParams;
	return clean({
		type: 'tuic', tag: 'proxy', server: hostname(url), server_port: Number(url.port || 443),
		uuid: decode(url.username), password: decode(url.password),
		congestion_control: p.get('congestion_control') || p.get('congestion-control'),
		udp_relay_mode: p.get('udp_relay_mode') || p.get('udp-relay-mode'), tls: tlsFrom(url, true),
	});
}

function parseBasic(url, type) {
	return clean({
		type, tag: 'proxy', server: hostname(url), server_port: Number(url.port || (type === 'http' ? 80 : 1080)),
		username: decode(url.username), password: decode(url.password),
		tls: type === 'http' && url.protocol === 'https:' ? tlsFrom(url, true) : undefined,
	});
}

function parseShadowsocks(raw) {
	const match = raw.match(/^ss:\/\/([^#?]+)([^#]*)?(?:#(.*))?$/i);
	if (!match) throw new Error('Invalid Shadowsocks link');
	let authority = match[1];
	let suffix = match[2] || '';
	if (!authority.includes('@')) {
		const decoded = decodeBase64(authority);
		const at = decoded.lastIndexOf('@');
		if (at < 0) throw new Error('Invalid Shadowsocks credentials');
		authority = decoded;
	}
	let credentials;
	let endpoint;
	const at = authority.lastIndexOf('@');
	if (at >= 0) {
		credentials = authority.slice(0, at);
		endpoint = authority.slice(at + 1) + suffix;
		if (!credentials.includes(':')) credentials = decodeBase64(credentials);
	} else {
		throw new Error('Invalid Shadowsocks endpoint');
	}
	const split = credentials.indexOf(':');
	if (split < 1) throw new Error('Invalid Shadowsocks method');
	const endpointUrl = new URL('http://' + endpoint.replace(/^\/?/, ''));
	const pluginValue = endpointUrl.searchParams.get('plugin') || '';
	const pluginParts = pluginValue.split(';');
	return clean({
		outbound: {
			type: 'shadowsocks', tag: 'proxy', server: hostname(endpointUrl), server_port: Number(endpointUrl.port),
			method: decode(credentials.slice(0, split)), password: decode(credentials.slice(split + 1)),
			plugin: pluginParts.shift(),
			plugin_opts: pluginParts.join(';'),
		},
		name: decode(match[3] || '') || 'Shadowsocks',
	});
}

function parseVmess(raw) {
	const value = JSON.parse(decodeBase64(raw.replace(/^vmess:\/\//i, '').split('#')[0]));
	const tlsEnabled = value.tls === 'tls' || value.tls === true;
	const fake = new URL(`vmess://${value.id}@${value.add}:${value.port || 443}`);
	Object.entries({
		type: value.net, host: value.host, path: value.path, serviceName: value.path,
		security: tlsEnabled ? 'tls' : '', sni: value.sni, alpn: value.alpn,
	}).forEach(([key, val]) => { if (val != null && val !== '') fake.searchParams.set(key, val); });
	return clean({
		outbound: {
			type: 'vmess', tag: 'proxy', server: value.add, server_port: Number(value.port || 443),
			uuid: value.id, security: value.scy || 'auto', alter_id: Number(value.aid || 0),
			tls: tlsFrom(fake, tlsEnabled), transport: transportFrom(fake),
		},
		name: value.ps || 'VMess',
	});
}

function parseShareLink(raw) {
	const value = String(raw || '').trim();
	if (!value) throw new Error('Link is empty');
	if (/^vmess:\/\//i.test(value)) return parseVmess(value);
	if (/^ss:\/\//i.test(value)) return parseShadowsocks(value);

	const url = new URL(value);
	const scheme = url.protocol.replace(':', '').toLowerCase();
	let outbound;
	switch (scheme) {
	case 'vless': outbound = parseVless(url); break;
	case 'trojan': outbound = parseTrojan(url); break;
	case 'hysteria2': case 'hy2': outbound = parseHysteria2(url); break;
	case 'hysteria': outbound = parseHysteria(url); break;
	case 'tuic': outbound = parseTuic(url); break;
	case 'socks': case 'socks5': outbound = parseBasic(url, 'socks'); break;
	case 'http': case 'https': outbound = parseBasic(url, 'http'); break;
	default: throw new Error(`Unsupported link scheme: ${scheme}`);
	}
	if (!outbound.server || !Number.isInteger(outbound.server_port) || outbound.server_port < 1 || outbound.server_port > 65535)
		throw new Error('Invalid server or port');
	return { outbound, name: tagFrom(url, outbound.type.toUpperCase()) };
}

const api = { parseShareLink };
if (typeof module !== 'undefined' && module.exports) module.exports = api;
return typeof baseclass !== 'undefined' ? baseclass.extend(api) : api;
