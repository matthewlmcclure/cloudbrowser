EventMonitor = require('../../lib/client/event_monitor')
EventEmitter = require('events').EventEmitter

class MockDocument extends EventEmitter
    addEventListener : () ->
        console.log("mockdoc#addEventListener")
        @listeners.push(arguments[0])
        @emit('addEventListener', arguments)

class MockServer extends EventEmitter
    processEvent : (event) ->
        @emit('processEvent', event)

exports['tests'] =
    'basic test' : (test) ->
        monitor = new EventMonitor(new MockDocument, new MockServer)
        test.notEqual(monitor, null)
        test.done()

    'test addEventListener' : (test) ->
        document = new MockDocument
        server = new MockServer
        # Small implementation detail here: 'click' is registered before
        # 'change' when registering default events.
        events = ['click', 'change', 'mouseover', 'dblclick']
        count = 0
        document.on 'addEventListener', (args) ->
            console.log('emit:')
            console.log(args)
            test.equal(args[0], events[count++])
            if count == events.length
                test.done()

        monitor = new EventMonitor(document, server)

        # It shouldn't add a listener for default events; we're already
        # listening on those.
        monitor.addEventListener(
            nodeID : 'node1'
            type : 'change'
            capturing : true)
        monitor.addEventListener(
            nodeID : 'node1'
            type : 'click'
            capturing : true)

        monitor.addEventListener(
            nodeID : 'node1'
            type : 'mouseover'
            capturing : true)
        # It shouldn't add a second listener for 'mouseover'.
        monitor.addEventListener(
            nodeID : 'node1'
            type : 'mouseover'
            capturing : true)

        monitor.addEventListener(
            nodeID : 'node1'
            type : 'dblclick'
            capturing : true)