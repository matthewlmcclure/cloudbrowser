EventProcessor       = require('./browser/event_processor') # TODO move this
TaggedNodeCollection = require('../shared/tagged_node_collection')
Browser              = require('./browser')
{serialize}          = require('./browser/dom/serializer')

#   TODO: where should resourceproxy live?
#       Maybe here instead of Browser?

# Serves 1 Browser to n clients.
class BrowserServer
    constructor : (opts) ->
        @id = opts.id
        @browser = new Browser(opts.id, opts.shared)
        @sockets = []
        @nodes = new TaggedNodeCollection()
        @events = new EventProcessor(this)

        ['DOMNodeInserted',
         'DOMNodeInsertedIntoDocument',
         'DOMNodeRemovedFromDocument',
         'DOMAttrModified',
         'DOMStyleChanged'
         'DOMPropertyModified'
         'DOMCharacterDataModified'
         'DocumentCreated'].forEach (event) =>
             @browser.on event, @["handle#{event}"]

        # TODO:
        #   'log'
        #   bandwidth measuring and logging etc should go here, since browser is protocol agnostic.
        #   some sort of page load event so we can resync.
        #       this should be 2 events:
        #           'pageLoading' - stop client updates and event processing
        #           'pageLoaded' - resumse
    
    broadcastEvent : (name, params) ->
        for socket in @sockets
            socket.emit(name, params)

    addSocket : (socket) ->
        cmds = serialize(@browser.window.document, @browser.resources)
        socket.emit 'loadFromSnapshot'
            nodes : cmds
            events : @events.getSnapshot()
            components : @browser.getSnapshot().components
        @sockets.push(socket)
        socket.on 'processEvent', @processEvent
        socket.on 'setAttribute', @processClientSetAttribute
        socket.on 'disconnect', () =>
            @sockets = (s for s in @sockets when s != socket)

    processEvent : (args ) =>
        @events.processEvent(args)

    processClientSetAttribute : (args) =>
        target = @nodes.get(args.target)
        {attribute, value} = args
        if attribute == 'src'
            return
        if attribute == 'selectedIndex'
            return target[attribute] = value
        target.setAttribute(attribute, value)

    handleDOMStyleChanged : (event) =>
        console.log("detected style change")
        @broadcastEvent 'changeStyle',
            target : event.target.__nodeID
            attribute : event.attribute
            value : event.value

    handleDOMPropertyModified : (event) =>
        @broadcastEvent 'setProperty',
            target   : event.target.__nodeID
            property : event.property
            value    : event.value

    handleDocumentCreated : (event) =>
        @nodes.add(event.target)

    # Tag all newly created nodes.
    # This seems cleaner than having serializer do the tagging.
    # TODO: this won't tag the document node.
    handleDOMNodeInserted : (event) =>
        if event.target.tagName != 'SCRIPT' &&
           event.target.parentNode.tagName != 'SCRIPT' &&
           !event.target.__nodeID
            @nodes.add(event.target)

    handleDOMCharacterDataModified : (event) =>
        @broadcastEvent 'setCharacterData',
            target : event.target.__nodeID
            value  : event.target.nodeValue

    # TODO: How can we handle removal/re-insertion efficiently?
    # TODO: what if serialization starts at an iframe?
    handleDOMNodeInsertedIntoDocument : (event) =>
        if event.target.tagName != 'SCRIPT' && event.target.parentNode.tagName != 'SCRIPT'
            node = event.target
            cmds = serialize(node, @browser.resources)
            # 'before' tells the client where to insert the top level node in
            # relation to its siblings.
            # We only need it for the top level node because nodes in its tree
            # are serialized in order.
            before = node.nextSibling
            while before?.tagName?.toLowerCase() == 'script'
                before = before.nextSibling
            cmds[0].before = before?.__nodeID
            @broadcastEvent 'attachSubtree', cmds

    handleDOMNodeRemovedFromDocument : (event) =>
        if event.target.tagName != 'SCRIPT' && event.relatedNode.tagName != 'SCRIPT'
            @broadcastEvent 'removeSubtree',
                parent : event.relatedNode.__nodeID
                node   : event.target.__nodeID

    # TODO: we want client to set these using properties, should we do
    #       the conversion from attribute name to property name here or on
    #       client?
    handleDOMAttrModified : (event) =>
        # Note: ADDITION can really be MODIFIED as well.
        if event.attrChange == 'ADDITION'
            @broadcastEvent 'setAttr',
                target : event.target.__nodeID
                name   : event.attrName
                value  : event.newValue
        else
            @broadcastEvent 'removeAttr',
                target : event.target.__nodeID
                name   : event.attrName
            
module.exports = BrowserServer
