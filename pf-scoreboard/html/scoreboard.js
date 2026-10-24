(function() {
    var mainElement = document.getElementById('scoreboard-main');
    var titleElement = document.getElementById('scoreboard-title');
    var subtitleElement = document.getElementById('scoreboard-subtitle');
    var progressElement = document.getElementById('scoreboard-progress');

    mainElement.style.display = 'none';

    window.addEventListener('message', function(event) {
        var data = event.data || {};

        if (data.action === 'scoreboard_open' || data.action === 'scoreboard_update') {
            if (data.title) titleElement.innerHTML = data.title;
            if (data.subtitle !== undefined) subtitleElement.innerHTML = data.subtitle;
            if (data.progress !== undefined) progressElement.innerHTML = data.progress;

            if (data.action === 'scoreboard_open') {
                mainElement.style.display = 'block';
                $('#scoreboard-main').animate({ 'margin-left': '2%' }, 500);
            }
        } else if (data.action === 'scoreboard_close') {
            $('#scoreboard-main').animate({ 'margin-left': '-30%' }, 500);
            setTimeout(function() {
                mainElement.style.display = 'none';
            }, 500);
        }
    });
})();
