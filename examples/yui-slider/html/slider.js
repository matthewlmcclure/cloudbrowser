YUI({ filter: 'raw' }).use("slider", function (Y) {

var control    = Y.one('#volume_control'),
    volInput   = Y.one('#volume'),
    icon       = Y.one('#volume_icon'),
    mute       = Y.one('#mute'),
    open       = false,
    level      = 2,
    beforeMute = 0,
    wait,
    volume;

// The style.top is known because of a fixed height control bar, but the
// style.left remains unknown until run time.
Y.one("#volume_slider").setStyle('left',icon.get('offsetLeft')+'px');

volume = new Y.Slider({
    axis  : 'y',
    min   : 100,
    max   : 0,
    value : 50,
    length: '105px'
});

volume.renderRail = function () {
    return Y.one( "#volume_slider span.yui3-slider-rail" );
};
volume.renderThumb = function () {
    return this.rail.one( "span.yui3-slider-thumb" );
};

volume.render( "#volume_slider" );

// Initialize event listeners
volume.after('valueChange', updateInput);
volume.after('valueChange', updateIcon);

mute.on('click', muteVolume);

volInput.on({
    keydown : handleInput,
    keyup   : updateVolume
});

icon.on('click', showHideSlider);

Y.one( 'doc' ).on('click', handleDocumentClick );

// Support functions
function updateInput(e) {
    if (e.src !== 'KEY') {
        volInput.set('value',e.newVal);
    }
}

function updateIcon(e) {
    var newLevel = e.newVal && Math.ceil(e.newVal / 34);

    if (level !== newLevel) {
        icon.replaceClass('level_'+level, 'level_'+newLevel);
        level = newLevel;
    }
}

function muteVolume(e) {
    var disabled = !volume.get('disabled');
    volume.set('disabled', disabled);

    if (disabled) {
        beforeMute = volume.getValue();
        volume.setValue(0);
        volInput.set('disabled','disabled');
    } else {
        volume.setValue(beforeMute);
        volInput.set('disabled','');
    }
}

function handleInput(e) {
    // Allow only numbers and various other control keys
    if (e.keyCode > 57) {
        e.halt();
    }
}

function updateVolume(e) {
    // delay input processing to give the user time to type
    if (wait) {
        wait.cancel();
    }

    wait = Y.later(400, null, function () {
        var value = parseInt(volInput.get('value'),10) || 0;

        if (value > 100) {
            volInput.set('value', 100);
            value = 100
        }

        volume.setValue( value );
    });
}

function showHideSlider(e) {
    control.toggleClass('volume-hide');
    open = !open;

    if (e) {
        e.preventDefault();
    }
}

function handleDocumentClick(e) {
    if (open && !icon.contains(e.target) &&
            !volume.get('boundingBox').contains(e.target)) {
        showHideSlider();
    }
}

});
