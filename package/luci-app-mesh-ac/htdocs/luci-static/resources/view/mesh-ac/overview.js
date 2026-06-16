'use strict';
'require view';
'require form';
'require fs';
'require uci';

function parseJson(raw, fallback) {
	try {
		return JSON.parse(raw || '');
	} catch (e) {
		return fallback;
	}
}

function optionValues(option, values) {
	values.forEach(function(value) {
		option.value(value, value === 'auto' ? _('Auto') : value);
	});
}

function modeLabel(mode) {
	if (mode === 'bridge')
		return _('Bridge');
	if (mode === 'gateway')
		return _('Gateway');
	return mode || _('Unknown');
}

function renderStatus(status) {
	var capabilities = status.capabilities || {};
	var network = status.network || {};
	var wifi = status.wifi || {};
	var actualMode = network.mode || 'unknown';
	var desiredMode = network.desired_mode || 'bridge';
	var rows = [
		[ _('Active network mode'), modeLabel(actualMode) ],
		[ _('Configured network mode'), modeLabel(desiredMode) ],
		[ _('LAN protocol'), network.lan_proto || _('Unknown') ],
		[ _('LAN IP'), network.lan_ip || '-' ],
		[ _('LAN DHCP'), network.dhcp_enabled ? _('Enabled') : _('Disabled') ],
		[ _('WAN in bridge'), network.wan_bridged ? _('Yes') : _('No') ]
	];
	if (capabilities.local_member) {
		rows.push(
			[ _('2.4 GHz SSID'), wifi.ssid_2g || '-' ],
			[ _('5 GHz SSID'), wifi.ssid_5g || '-' ],
			[ _('Backhaul Mesh ID'), wifi.mesh_id || '-' ]
		);
	}
	var tableRows = rows.map(function(row) {
		return E('tr', {}, [ E('td', {}, row[0]), E('td', {}, row[1]) ]);
	});
	var children = [
		E('h3', _('Current active state')),
		E('table', { 'class': 'table' }, tableRows)
	];

	if ((actualMode === 'bridge' || actualMode === 'gateway') && actualMode !== desiredMode) {
		children.push(E('div', { 'class': 'alert-message warning' },
			_('The saved network mode does not match the active network state. The selector below is initialized from the active state to avoid showing a stale mode.')));
	}

	return E('div', { 'class': 'cbi-section' }, children);
}

function formatLastSeen(value) {
	var timestamp = Number(value || 0);
	var diff;

	if (!timestamp)
		return '-';

	diff = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
	if (diff < 90)
		return _('%ds ago').format(diff);
	if (diff < 3600)
		return _('%dm ago').format(Math.floor(diff / 60));
	if (diff < 86400)
		return _('%dh ago').format(Math.floor(diff / 3600));
	return new Date(timestamp * 1000).toLocaleString();
}

function onlineLabel(value) {
	var timestamp = Number(value || 0);

	return timestamp && ((Date.now() / 1000) - timestamp) < 120
		? _('Online')
		: _('Offline');
}

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/usr/sbin/mesh-ac-list'), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/mesh-ac-status'), { stdout: '{}' }),
			uci.load('mesh_ac')
		]);
	},

	render: function(data) {
		var m, s, o;
		var nodes = (data[0].stdout || '').trim().split(/\n+/).filter(Boolean);
		var status = parseJson(data[1].stdout, {});
		var capabilities = status.capabilities || {};
		var localMemberSupported = !!capabilities.local_member;
		var activeMode = status.network && status.network.mode;
		var legacySsid = uci.get('mesh_ac', 'main', 'ssid') || 'OpenWrt-Mesh';

		m = new form.Map('mesh_ac', _('Mesh AC'));
		s = m.section(form.NamedSection, 'main', 'controller', _('Controller'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable AC'));
		o.default = '1';
		o = s.option(form.Flag, 'pairing_enabled', _('Allow pairing'));
		o.default = '1';
		if (localMemberSupported) {
			o = s.option(form.Flag, 'local_member', _('Enable AC local mesh member'));
			o.default = '0';
			o = s.option(form.ListValue, 'network_mode', _('Network mode'));
			o.value('bridge', _('Bridge'));
			o.value('gateway', _('Gateway'));
			o.default = 'bridge';
			o.cfgvalue = function(section_id) {
				if (activeMode === 'bridge' || activeMode === 'gateway')
					return activeMode;
				return uci.get('mesh_ac', section_id, 'network_mode') || 'bridge';
			};
			o = s.option(form.Value, 'network_cidr', _('Gateway LAN CIDR'));
			o.default = '192.168.50.0/24';
			o.depends('network_mode', 'gateway');
		}

		o = s.option(form.Value, 'ssid_2g', _('2.4 GHz client SSID'));
		o.default = legacySsid;
		o.cfgvalue = function(section_id) {
			return uci.get('mesh_ac', section_id, 'ssid_2g') || legacySsid;
		};
		o = s.option(form.Value, 'ssid_5g', _('5 GHz client SSID'));
		o.default = legacySsid;
		o.cfgvalue = function(section_id) {
			return uci.get('mesh_ac', section_id, 'ssid_5g') || legacySsid;
		};
		o = s.option(form.Value, 'key', _('Client password'));
		o.password = true;
		s.option(form.Value, 'country', _('Country'));
		s.option(form.Value, 'mobility_domain', _('Mobility domain'));
		s.option(form.Flag, 'ieee80211k', _('802.11k'));
		s.option(form.Flag, 'ieee80211v', _('802.11v'));
		s.option(form.Flag, 'ieee80211r', _('802.11r'));

		s.option(form.Value, 'mesh_id', _('Mesh ID'));
		o = s.option(form.Value, 'mesh_key', _('Mesh key'));
		o.password = true;
		o = s.option(form.ListValue, 'band', _('Wireless backhaul band'));
		o.value('5g', '5 GHz');
		o.value('2g', '2.4 GHz');

		o = s.option(form.ListValue, 'channel_5g', _('5 GHz channel'));
		optionValues(o, ['auto', '36', '40', '44', '48', '52', '56', '60', '64', '100', '104', '108', '112', '116', '120', '124', '128', '132', '136', '140', '144', '149', '153', '157', '161', '165']);
		o.default = '149';
		o = s.option(form.ListValue, 'htmode_5g', _('5 GHz mode'));
		optionValues(o, ['HE80', 'HE160', 'HE40', 'HE20', 'VHT80', 'VHT160', 'VHT40', 'VHT20']);
		o.default = 'HE80';
		o = s.option(form.ListValue, 'channel_2g', _('2.4 GHz channel'));
		optionValues(o, ['auto', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13']);
		o.default = '6';
		o = s.option(form.ListValue, 'htmode_2g', _('2.4 GHz mode'));
		optionValues(o, ['HE20', 'HE40', 'HT20', 'HT40']);
		o.default = 'HE20';
		s.option(form.Flag, 'wired_preferred', _('Prefer wired backhaul'));

		s.option(form.Flag, 'dawn_enabled', _('Enable DAWN'));
		s.option(form.Value, 'dawn_kicking', _('DAWN kicking mode'));
		s.option(form.Flag, 'dawn_set_hostapd_nr', _('DAWN neighbor reports'));

		var table = E('div', { 'class': 'cbi-section' }, [
			E('h3', _('Managed APs')),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [
					E('th', _('Node')),
					E('th', _('MAC')),
					E('th', _('IP')),
					E('th', _('Status')),
					E('th', _('Last seen'))
				])
			])
		]);
		var tbody = table.querySelector('table');

		nodes.forEach(function(line) {
			var node;
			try { node = JSON.parse(line); } catch (e) { return; }
			tbody.appendChild(E('tr', {}, [
				E('td', node.id || ''),
				E('td', node.mac || ''),
				E('td', node.ip || ''),
				E('td', onlineLabel(node.last_seen)),
				E('td', formatLastSeen(node.last_seen))
			]));
		}, this);

		return m.render().then(function(mapEl) {
			var children = [];

			if (localMemberSupported)
				children.push(renderStatus(status));
			children.push(mapEl, table);
			return E([], children);
		});
	}
});
