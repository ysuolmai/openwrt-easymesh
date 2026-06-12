'use strict';
'require view';
'require form';
'require fs';
'require ui';

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(fs.exec('/usr/sbin/mesh-ac-list'), { stdout: '' })
		]);
	},

	render: function(data) {
		var m, s, o;
		var nodes = (data[0].stdout || '').trim().split(/
+/).filter(Boolean);

		m = new form.Map('mesh_ac', _('Mesh AC'));
		s = m.section(form.NamedSection, 'main', 'controller', _('Controller'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enable AC'));
		o.default = '1';
		o = s.option(form.Flag, 'pairing_enabled', _('Allow pairing'));
		o.default = '1';
		o = s.option(form.Value, 'pairing_token', _('Pairing token'));
		o.password = true;

		s.option(form.Value, 'ssid', _('Client SSID'));
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
		s.option(form.Value, 'channel_5g', _('5 GHz channel'));
		s.option(form.Value, 'htmode_5g', _('5 GHz mode'));
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
					E('th', _('Approved')),
					E('th', _('Action'))
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
				E('td', String(node.approved)),
				E('td', {}, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, function() {
							return fs.exec('/usr/sbin/mesh-ac-approve', [ node.id ]).then(function() {
								location.reload();
							});
						})
					}, _('Approve'))
				])
			]));
		}, this);

		return Promise.resolve(E([], [ m.render(), table ]));
	}
});
