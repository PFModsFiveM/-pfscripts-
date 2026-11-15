/* pf-hud: the page's message router (classic script, loaded first).
 *
 *   PfHud.on('action', fn)      fn(data) for every NUI message with that action
 *   PfHud.dispatch(data)        hand a message to its handlers (the dial forwards some)
 *   PfHud.post('event', data)   a NUI callback to the client (a promise; nothing outside FiveM)
 *
 * Only what FiveM sends is taken: SendNUIMessage arrives from this page itself (no source) or from the root page that
 * hosts the frames; a sibling resource's frame posting into this one is neither and is dropped (as WHIP's main.js). */
(function (root) {
    "use strict";
    const handlers = Object.create(null);

    function fromFiveM(event) {
        const s = event.source;
        return s === null || s === undefined || s === root || s === root.parent || s === root.top;
    }

    const resource = typeof root.GetParentResourceName === "function" ? root.GetParentResourceName() : "pf-hud";

    const PfHud = {
        resource,
        on(action, fn) {
            if (typeof fn !== "function") return;
            (handlers[action] || (handlers[action] = [])).push(fn);
        },
        dispatch(d) {
            if (!d || typeof d !== "object" || typeof d.action !== "string") return;
            const list = handlers[d.action];
            if (!list) return;
            for (let i = 0; i < list.length; i++) {
                try { list[i](d); } catch (err) { console.error(`[pf-hud] ${d.action}:`, err); }
            }
        },
        post(event, data) {
            try {
                return root.fetch(`https://${resource}/${event}`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json; charset=UTF-8" },
                    body: JSON.stringify(data == null ? {} : data),
                }).catch(() => null);
            } catch (e) {
                return Promise.resolve(null);
            }
        },
    };
    root.PfHud = PfHud;

    root.addEventListener("message", (event) => {
        if (!fromFiveM(event)) return;
        PfHud.dispatch(event.data);
    });
})(window);
