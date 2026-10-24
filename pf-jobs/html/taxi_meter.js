$(document).ready(function () {
    const meterElement = $('#taxi-meter');

    const meterData = {
        visible: false,
        onJob: true,
        currentFare: 0,
        rawFare: 0,
        penaltyAmount: 0,
        penaltyPct: 0,
        distance: 0,
        rate: 60,
        collisions: 0,
        collisionTypeCounts: {
            pedestrian: 0,
            vehicle: 0,
            sign_lamp: 0,
            wall: 0,
        },
        lastCollisionType: null,
        passengerName: 'Customer',
        passengerType: 'standard',
    };

    window.addEventListener('message', function (event) {
        const data = event.data || {};

        switch (data.action) {
            case 'showTaxiMeter':
                showMeter(data);
                break;
            case 'hideTaxiMeter':
                hideMeter();
                break;
            case 'updateTaxiMeter':
                updateMeter(data);
                break;
            case 'recordCollision':
                recordCollision(data);
                break;
            default:
                break;
        }
    });

    function showMeter(data) {
        meterData.visible = true;
        meterData.onJob = data.onJob !== undefined ? data.onJob : true;
        meterData.currentFare = Number(data.currentFare || 0);
        meterData.rawFare = Number(data.rawFare || meterData.currentFare || 0);
        meterData.penaltyAmount = Number(data.penaltyAmount || 0);
        meterData.penaltyPct = Number(data.penaltyPct || 0);
        meterData.distance = Number(data.distance || 0);
        meterData.rate = Number(data.rate || 60);
        meterData.collisions = Number(data.collisions || 0);
        meterData.collisionTypeCounts = data.collisionTypeCounts || meterData.collisionTypeCounts;
        meterData.lastCollisionType = data.lastCollisionType || null;
        meterData.passengerName = data.passengerName || 'Customer';
        meterData.passengerType = data.passengerType || 'standard';

        updateBadge();
        updateMeterDisplay();
        meterElement.removeClass('hidden');
    }

    function hideMeter() {
        meterData.visible = false;
        meterElement.addClass('hidden');
    }

    function updateMeter(data) {
        if (!meterData.visible) return;

        if (data.onJob !== undefined) meterData.onJob = !!data.onJob;
        if (data.currentFare !== undefined) meterData.currentFare = Number(data.currentFare || 0);
        if (data.rawFare !== undefined) meterData.rawFare = Number(data.rawFare || 0);
        if (data.penaltyAmount !== undefined) meterData.penaltyAmount = Number(data.penaltyAmount || 0);
        if (data.penaltyPct !== undefined) meterData.penaltyPct = Number(data.penaltyPct || 0);
        if (data.distance !== undefined) meterData.distance = Number(data.distance || 0);
        if (data.rate !== undefined) meterData.rate = Number(data.rate || 60);
        if (data.collisions !== undefined) meterData.collisions = Number(data.collisions || 0);
        if (data.collisionTypeCounts !== undefined) meterData.collisionTypeCounts = data.collisionTypeCounts || meterData.collisionTypeCounts;
        if (data.lastCollisionType !== undefined) meterData.lastCollisionType = data.lastCollisionType;
        if (data.passengerName !== undefined) meterData.passengerName = data.passengerName || 'Customer';
        if (data.passengerType !== undefined) meterData.passengerType = data.passengerType || 'standard';

        updateBadge();
        updateMeterDisplay();
    }

    function recordCollision(data) {
        if (!meterData.visible) return;

        if (data && data.collisionType) {
            meterData.lastCollisionType = data.collisionType;
        }

        const collisionStat = $('#collision-stat');
        collisionStat.addClass('active');
        setTimeout(function () {
            collisionStat.removeClass('active');
        }, 400);
    }

    function updateBadge() {
        $('#passenger-name').text(meterData.passengerName);

        const badge = $('#passenger-badge');
        badge.removeClass('vip premium standard');

        if (meterData.passengerType === 'vip') {
            badge.addClass('vip').text('VIP');
        } else if (meterData.passengerType === 'premium') {
            badge.addClass('premium').text('PREMIUM');
        } else {
            badge.addClass('standard').text('STANDARD');
        }
    }

    function updateMeterDisplay() {
        $('#meter-status').text(meterData.onJob ? 'JOB RIDE' : 'MANUAL');

        const fare = Math.max(0, Math.floor(meterData.currentFare || 0));
        const rawFare = Math.max(0, Math.floor(meterData.rawFare || 0));
        const penaltyAmount = Math.max(0, Math.floor(meterData.penaltyAmount || 0));
        const penaltyPct = Math.max(0, Number(meterData.penaltyPct || 0));

        $('#fare-amount').text('$' + fare.toLocaleString());
        $('#raw-fare').text('Raw: $' + rawFare.toLocaleString());
        $('#distance-value').text((meterData.distance || 0).toFixed(2) + ' mi');
        $('#rate-value').text('$' + Math.floor(meterData.rate || 60) + '/mi');
        $('#collision-count').text(Math.max(0, Math.floor(meterData.collisions || 0)).toString());
        $('#penalty-amount').text('-$' + penaltyAmount.toLocaleString());
        $('#penalty-percent').text('-' + Math.round(penaltyPct * 100) + '%');

        const lastType = meterData.lastCollisionType ? String(meterData.lastCollisionType) : 'none';
        $('#last-collision-type').text('Last: ' + lastType);
    }
});
