'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * v0.1: live status + token confirm. The full pre-flash arming page (token
 * held in JS memory, polling across the reboot, auto-confirm on first
 * answer) lands in a later version — see README roadmap.
 */

var callStatus = rpc.declare({
	object: 'sysupgrade-confirm',
	method: 'status',
	expect: { }
});

var callConfirm = rpc.declare({
	object: 'sysupgrade-confirm',
	method: 'confirm',
	params: [ 'token' ],
	expect: { }
});

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(status) {
		var self = this;
		var statusNode = E('div', { 'class': 'cbi-section' });

		var renderStatus = function(s) {
			var rows = [];
			if (s && s.pending) {
				rows.push(E('p', {}, [ E('strong', {}, _('UNCONFIRMED firmware is running.')) ]));
				rows.push(E('p', {}, _('Booted partition value: %s (was %s before the flash)')
					.format(s.boot_part || '?', s.armed_from || '?')));
				rows.push(E('p', {}, _('Automatic revert in %s seconds unless confirmed.')
					.format(s.remaining)));
			}
			else {
				rows.push(E('p', {}, _('No pending sysupgrade — running firmware is confirmed.')));
				rows.push(E('p', {}, _('Current boot partition value: %s').format((s && s.boot_part) || '?')));
			}
			while (statusNode.firstChild)
				statusNode.removeChild(statusNode.firstChild);
			rows.forEach(function(r) { statusNode.appendChild(r); });
		};

		renderStatus(status);

		poll.add(function() {
			return callStatus().then(renderStatus);
		}, 5);

		var tokenInput = E('input', { 'type': 'text', 'class': 'cbi-input-text',
			'placeholder': _('confirm token (printed at arm time)') });

		var confirmBtn = E('button', {
			'class': 'cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				return callConfirm(tokenInput.value).then(function(res) {
					if (res && res.confirmed)
						ui.addNotification(null, E('p', _('Firmware confirmed — revert timer disarmed.')), 'info');
					else
						ui.addNotification(null, E('p', _('Confirm rejected (bad or missing token). Admins can always confirm over SSH: sysupgrade-confirm')), 'warning');
				});
			})
		}, _('Confirm firmware'));

		return E('div', {}, [
			E('h2', {}, _('Sysupgrade Confirm')),
			statusNode,
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Confirming commits the currently running firmware and cancels the automatic revert.')),
				tokenInput, ' ', confirmBtn
			])
		]);
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
