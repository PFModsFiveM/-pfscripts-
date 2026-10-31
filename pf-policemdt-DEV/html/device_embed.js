// The MDT page inside the tablet or the computer (pf-devices iframe app, ?embed=1&device=...).
// Same page, same code: this only fits it to the device window, makes callbacks reach this
// resource from inside the device's page, and tells the client when the window opens and closes.
(function () {
    const params = new URLSearchParams(window.location.search);
    if (params.get('embed') !== '1') return;
    document.documentElement.classList.add('pf-embedded');
    if (document.body) document.body.classList.add('pf-embedded');
    else document.addEventListener('DOMContentLoaded', () => document.body.classList.add('pf-embedded'));

    // inside an iframe GetParentResourceName can name the device; the host is always this resource
    const own = (window.location.hostname || '').replace(/^cfx-nui-/, '');
    if (own) window.getResourceName = function () { return own; };

    function post(name, data, keepalive) {
        return fetch(`https://${own}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
            keepalive: keepalive === true,
        }).catch(() => {});
    }

    window.addEventListener('pagehide', () => post('pfDeviceClosed', {}, true));
    const start = () => post('pfDeviceOpen', { device: params.get('device') || 'tablet' });
    if (document.readyState === 'complete') start();
    else window.addEventListener('load', start);
})();
