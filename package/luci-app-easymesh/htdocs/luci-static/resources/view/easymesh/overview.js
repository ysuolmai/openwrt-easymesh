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

function hasValue(value) {
	return value !== null && value !== undefined && value !== "";
}

function preferActive(activeValue, savedValue, fallback) {
	if (hasValue(activeValue))
		return activeValue;
	if (hasValue(savedValue))
		return savedValue;
	return fallback;
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
			L.resolveDefault(fs.exec('/usr/sbin/easymesh-list'), { stdout: '' }),
			L.resolveDefault(fs.exec('/usr/sbin/easymesh-status'), { stdout: '{}' }),
			uci.load('easymesh')
		]);
	},

	render: function(data) {
		var m, s, o;
		var nodes = (data[0].stdout || '').trim().split(/\n+/).filter(Boolean);
		var status = parseJson(data[1].stdout, {});
		var capabilities = status.capabilities || {};
		var network = status.network || {};
		var wifi = status.wifi || {};
		var localMemberSupported = !!capabilities.local_member;
		var localMemberActive = !!wifi.local_member_active || !!wifi.mesh_id || !!wifi.ssid_2g || !!wifi.ssid_5g;
		var activeMode = network.mode;
		var legacySsid = uci.get('easymesh', 'main', 'ssid') || 'OpenWrt-Mesh';

		function currentValue(activeValue, option, fallback) {
			return function(section_id) {
				return preferActive(activeValue, uci.get('easymesh', section_id, option), fallback);
			};
		}

		function currentWifiValue(activeValue, option, fallback) {
			return currentValue(localMemberSupported ? activeValue : null, option, fallback);
		}

		m = new form.Map('easymesh', _('EasyMesh'));
		s = m.section(form.NamedSection, 'main', 'controller', _('Controller'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable AC'));
		o.default = '1';
		o = s.option(form.Flag, 'pairing_enabled', _('Allow pairing'));
		o.default = '1';
		if (localMemberSupported) {
			o = s.option(form.Flag, 'local_member', _('Enable AC local mesh member'));
			o.default = '1';
			o.cfgvalue = function() {
				return localMemberActive ? '1' : '0';
			};
			o = s.option(form.ListValue, 'network_mode', _('Network mode'));
			o.value('gateway', _('Gateway'));
			o.value('bridge', _('Bridge'));
			o.default = 'gateway';
			o.cfgvalue = function(section_id) {
				if (activeMode === 'bridge' || activeMode === 'gateway')
					return activeMode;
				return uci.get('easymesh', section_id, 'network_mode') || 'gateway';
			};
			o = s.option(form.Value, 'network_cidr', _('Gateway LAN CIDR'));
			o.default = '192.168.10.0/24';
			o.cfgvalue = currentValue(null, 'network_cidr', '192.168.10.0/24');
			o.depends('network_mode', 'gateway');
		}

		o = s.option(form.Value, 'ssid_2g', _('2.4 GHz client SSID'));
		o.default = legacySsid;
		o.cfgvalue = currentWifiValue(wifi.ssid_2g, 'ssid_2g', legacySsid);
		o = s.option(form.Value, 'ssid_5g', _('5 GHz client SSID'));
		o.default = legacySsid;
		o.cfgvalue = currentWifiValue(wifi.ssid_5g, 'ssid_5g', legacySsid);
		o = s.option(form.Value, 'key', _('Client password'));
		o.password = true;
		o.cfgvalue = currentWifiValue(wifi.key, 'key', '12345678');
		o = s.option(form.Value, 'country', _('Country'));
		o.cfgvalue = currentWifiValue(wifi.country, 'country', 'US');
		o = s.option(form.Value, 'mobility_domain', _('Mobility domain'));
		o.cfgvalue = currentWifiValue(wifi.mobility_domain, 'mobility_domain', '4f57');
		o = s.option(form.Flag, 'ieee80211k', _('802.11k'));
		o.cfgvalue = currentWifiValue(wifi.ieee80211k, 'ieee80211k', '1');
		o = s.option(form.Flag, 'ieee80211v', _('802.11v'));
		o.cfgvalue = currentWifiValue(wifi.ieee80211v, 'ieee80211v', '1');
		o = s.option(form.Flag, 'ieee80211r', _('802.11r'));
		o.cfgvalue = currentWifiValue(wifi.ieee80211r, 'ieee80211r', '1');

		o = s.option(form.Value, 'mesh_id', _('Mesh ID'));
		o.cfgvalue = currentWifiValue(wifi.mesh_id, 'mesh_id', 'openwrt-easymesh-backhaul');
		o = s.option(form.Value, 'mesh_key', _('Mesh key'));
		o.password = true;
		o.cfgvalue = currentWifiValue(wifi.mesh_key, 'mesh_key', '12345678');
		o = s.option(form.ListValue, 'band', _('Wireless backhaul band'));
		o.value('5g', '5 GHz');
		o.value('2g', '2.4 GHz');
		o.cfgvalue = currentWifiValue(wifi.band, 'band', '5g');

		o = s.option(form.ListValue, 'channel_5g', _('5 GHz channel'));
		optionValues(o, ['auto', '36', '40', '44', '48', '52', '56', '60', '64', '100', '104', '108', '112', '116', '120', '124', '128', '132', '136', '140', '144', '149', '153', '157', '161', '165']);
		o.default = '149';
		o.cfgvalue = currentWifiValue(wifi.channel_5g, 'channel_5g', '149');
		o = s.option(form.ListValue, 'htmode_5g', _('5 GHz mode'));
		optionValues(o, ['HE80', 'HE160', 'HE40', 'HE20', 'VHT80', 'VHT160', 'VHT40', 'VHT20']);
		o.default = 'HE80';
		o.cfgvalue = currentWifiValue(wifi.htmode_5g, 'htmode_5g', 'HE80');
		o = s.option(form.ListValue, 'channel_2g', _('2.4 GHz channel'));
		optionValues(o, ['auto', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13']);
		o.default = '6';
		o.cfgvalue = currentWifiValue(wifi.channel_2g, 'channel_2g', '6');
		o = s.option(form.ListValue, 'htmode_2g', _('2.4 GHz mode'));
		optionValues(o, ['HE20', 'HE40', 'HT20', 'HT40']);
		o.default = 'HE20';
		o.cfgvalue = currentWifiValue(wifi.htmode_2g, 'htmode_2g', 'HE20');
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
			return E([], [ mapEl, table ]);
		});
	}
});
