# TODO: form handling
# TODO: JSDOM is missing defaultValue and defaultChecked setters for HTMLInputElement
# TODO: JSDOM is missing defaultValue for HTMLTextAreaElement
# TODO: entity reference, notationnode?
# TODO: How should we handle cookie?

isDOMNode = (node) -> (node?.ELEMENT_NODE == 1)

# dom - the jsdom dom implementation
# wrapper - must have emit and nodes
# TODO: rename params, cause dom is the jsdom dom, wrappers is DOM.  that is dumb.
exports.addAdvice = (dom, wrapper) ->
    # TODO: change event names to DOMMethod and DOMProperty

    # func gets passed the original return value and the 'this' value.
    # If func returns true, then we will echo this property update.
    # Otherwise, we just return the rv.
    wrapProperty = (obj, prop, func) ->
        originalSetter = obj.__lookupSetter__(prop)
        if !originalSetter?
            throw new Error "Missing a setter for #{prop}"
        obj.__defineSetter__(prop, (value) ->
            #console.log("#{prop} called")
            rv = originalSetter.call(this, value)
            if !func? || func(this, arguments, rv)
                if value?.__nodeID?
                    value = wrapper.nodes.get(value.__nodeID)
                params =
                    targetID : this.__nodeID
                    prop : prop
                    value : value
                wrapper.emit('DOMPropertyUpdate', params)
            return rv
        )

    wrapMethod = (obj, name, func) ->
        originalMethod = obj[name]
        obj[name] = ->
            #console.log("#{name} called #{arguments[0]}")
            rv = originalMethod.apply(this, arguments)
            # Don't allow any operations on scripts to get to client.
            if (rv?.tagName?.toLowerCase() == 'script') ||
               (this?.tagName?.toLowerCase() == 'script')
                return rv
            if isDOMNode(rv) && (rv.__nodeID == undefined)
                wrapper.nodes.add(rv)
            if !func? || func(this, arguments, rv)
                rvID = if rv? then rv.__nodeID else null
                params =
                    targetID : this.__nodeID
                    rvID : rvID
                    method : name
                    args : wrapper.nodes.scrub(arguments)
                wrapper.emit('DOMUpdate', params)
            return rv

    # w3c Level 2 Core
    # NOTE: we don't wrap appendChild because JSDOM implements it using
    # insertBefore, so wrapping it would cause duplicate instructions.
    # We don't wrap cloneNode because it calls already wrapped DOM
    # methods behind the scenes
    for method in ['insertBefore', 'replaceChild', 'removeChild']
        wrapMethod(dom.Node.prototype, method)
    wrapProperty(dom.Node.prototype, 'nodeValue')

    # Note: have to use this methods variable for multi-line arrays in a for/in
    # loop or else coffee-script complains.
    methods = ['setAttribute', 'setAttributeNS',
               'removeAttribute', 'removeAttributeNS']
    for method in methods
        do (method) ->
            wrapMethod(dom.Element.prototype, method, (elem, args, rv) ->
                tagName = elem.tagName.toLowerCase()
                attr = null
                value = null
                if /NS$/.test(method)
                    attr = args[1].toLowerCase()
                    if args.length > 2
                        value = args[1]
                else
                    attr = args[0].toLowerCase()
                    if args.length > 1
                        value = args[1]
                if attr == 'src'
                    if tagName == 'iframe' || tagName == 'frame'
                        # There is still special handling to be done in this
                        # case, but we need to do it after the
                        # HTMLFrameElement's function has been called.
                        return false
                    console.log("FOUND A URL IN ADVICE TODO: RESOURCEPROXY")
                return true
            )

    methods = ['setAttributeNode', 'setAttributeNodeNS',
               'removeAttributeNode', 'removeAttributeNodeNS']
    for method in methods
        do (method) ->
            wrapMethod(dom.Element.prototype, method, (elem, args, rv) ->
                tagName = elem.tagName.toLowerCase()
                attr = args[0] # Attribute node
                if tagName == 'iframe' || tagName == 'frame'
                    if attr.name.toLowerCase() == 'src'
                        return false
                return true
            )

    for method in ['setAttribute', 'setAttributeNS']
        do (method) ->
            wrapMethod(dom.HTMLFrameElement.prototype, method, (elem, args, rv) ->
                tagName = elem.tagName.toLowerCase()
                attr = if /NS$/.test(method)
                    args[1].toLowerCase()
                else
                    args[0].toLowerCase()
                # If src attribute is set, jsdom will create/load a new document.
                if attr == 'src'
                    # We need to wait for load because that means that the old
                    # Document has been deleted, and the new one has been
                    # created.
                    elem.addEventListener('load', () ->
                        # At this point, JSDOM has deleted the old document
                        # and created the new one, so we can (and should) go
                        # ahead and tag it.
                        wrapper.nodes.add(elem.contentDocument)
                        # Next, we need to clean out the client's iframe, since
                        # setting src creates a new iframe on the server.
                        wrapper.emit('clear', frame : elem.__nodeID)
                        # Then tag the document with its new ID.
                        wrapper.emit('tagDocument',
                            parent : elem.__nodeID
                            id : elem.contentDocument.__nodeID
                        )
                    )
                return false
            )

    methods = ['createTextNode', 'createAttribute', 'createDocumentFragment',
               'createComment', 'createCDATASection', 'importNode',
               'createAttributeNS']
    for method in methods
        wrapMethod(dom.Document.prototype, method)

    for method in ['createElement', 'createElementNS']
        do (method) ->
            wrapMethod(dom.Document.prototype, method, (elem, args, rv) ->
                tagName =
                    if /NS$/.test(method)
                        args[1].toLowerCase()
                    else
                        args[0].toLowerCase()
                if tagName == 'iframe' || tagName == 'frame'
                    # Note: this Document will be discarded if src is set, but
                    # we still need to support iframes that are created
                    # programatically.
                    wrapper.nodes.add(rv.contentDocument)
                    # We need to emit the DOMUpdate before we can tag the
                    # iframe's document.  We have to do it here since we can't
                    # tell the caller to tag the document after, and we don't
                    # want to add the special case check to every single
                    # method invocation by putting it in the advice.
                    wrapper.emit('DOMUpdate'
                        targetID : elem.__nodeID
                        rvID : rv.__nodeID
                        method : method
                        args : wrapper.nodes.scrub(args))
                    wrapper.emit('tagDocument',
                        parent : rv.__nodeID
                        id : rv.contentDocument.__nodeID)
                    # We return false because we already emitted the instruction.
                    return false
                return true
            )

    for method in ['appendData', 'insertData', 'deleteData', 'replaceData']
        wrapMethod(dom.CharacterData.prototype, method)
    wrapProperty(dom.CharacterData.prototype, 'data')
    wrapProperty(dom.Attr.prototype, 'value')
    wrapMethod(dom.Text.prototype, 'splitText')
    wrapProperty(dom.Text.prototype, 'value')

    # w3c Level 2 HTML
    # Note: most of the properties on HTML elements are implemented with
    # setters that call setAttribute behind the scenes, so we don't have
    # to wrap them.
    for property in ['title', 'cookie']
        wrapProperty(dom.HTMLDocument.prototype, property)
    wrapProperty(dom.HTMLTitleElement.prototype, 'text')
    wrapProperty(dom.HTMLMetaElement.prototype, 'httpEquiv')
    wrapProperty(dom.HTMLIsIndexElement.prototype, 'prompt')
    for method in ['submit', 'reset']
        wrapMethod(dom.HTMLFormElement.prototype, method)
    for method in  ['add', 'remove', 'blur', 'focus']
        wrapMethod(dom.HTMLSelectElement.prototype, method)
    for property in ['selectedIndex', 'value']
        wrapProperty(dom.HTMLSelectElement.prototype, property)
    for property in ['selected']
        wrapProperty(dom.HTMLOptionElement.prototype, property)

    for method in ['blur', 'focus', 'select']
        wrapMethod(dom.HTMLTextAreaElement.prototype, method)
    for method in ['blur', 'focus']
        wrapMethod(dom.HTMLAnchorElement.prototype, method)
    methods = ['createTHead', 'deleteTHead', 'createTFoot', 'deleteTFoot',
               'createCaption', 'deleteCaption', 'insertRow', 'deleteRow']
    for method in methods
        wrapMethod(dom.HTMLTableElement.prototype, method)
    for method in ['insertRow', 'deleteRow']
        wrapMethod(dom.HTMLTableSectionElement.prototype, method)
    for method in ['insertCell', 'deleteCell']
        wrapMethod(dom.HTMLTableRowElement.prototype, method)
    wrapProperty(dom.HTMLTableCellElement.prototype, 'headers')

    wrapProperty(dom.HTMLInputElement.prototype, 'checked')
    wrapProperty(dom.HTMLInputElement.prototype, 'value')


exports.wrapStyle = (dom, wrapper) ->
    # JSDOM level2/style.js uses the style getter to lazily create the 
    # CSSStyleDeclaration object for the element.  To be able to emit
    # the right instruction in the style object advice, we need to have
    # a pointer to the element that owns the style object, so we create it
    # here.
    do () ->
        proto = dom.HTMLElement.prototype
        getter = proto.__lookupGetter__('style')
        proto.__defineGetter__ 'style', () ->
            style = getter.call(this)
            style._parentElement = this
            return style

    # This list is from:
    #   http://dev.w3.org/csswg/cssom/#the-cssstyledeclaration-interface
    cssAttrs = [
        'azimuth', 'background', 'backgroundAttachment', 'backgroundColor',
        'backgroundImage', 'backgroundPosition', 'backgroundRepeat', 'border',
        'borderCollapse', 'borderColor', 'borderSpacing', 'borderStyle',
        'borderTop', 'borderRight', 'borderBottom', 'borderLeft',
        'borderTopColor', 'borderRightColor', 'borderBottomColor',
        'borderLeftColor', 'borderTopStyle', 'borderRightStyle',
        'borderBottomStyle', 'borderLeftStyle', 'borderTopWidth',
        'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
        'borderWidth', 'bottom', 'captionSide', 'clear', 'clip', 'color',
        'content', 'counterIncrement', 'counterReset', 'cue', 'cueAfter',
        'cueBefore', 'cursor', 'direction', 'display', 'elevation',
        'emptyCells', 'cssFloat', 'font', 'fontFamily', 'fontSize',
        'fontSizeAdjust', 'fontStretch', 'fontStyle', 'fontVariant',
        'fontWeight', 'height', 'left', 'letterSpacing', 'lineHeight',
        'listStyle', 'listStyleImage', 'listStylePosition', 'listStyleType',
        'margin', 'marginTop', 'marginRight', 'marginBottom', 'marginLeft',
        'markerOffset', 'marks', 'maxHeight', 'maxWidth', 'minHeight',
        'minWidth', 'orphans', 'outline', 'outlineColor', 'outlineStyle',
        'outlineWidth', 'overflow', 'padding', 'paddingTop', 'paddingRight',
        'paddingBottom', 'paddingLeft', 'page', 'pageBreakAfter',
        'pageBreakBefore', 'pageBreakInside', 'pause', 'pauseAfter',
        'pauseBefore', 'pitch', 'pitchRange', 'playDuring', 'position',
        'quotes', 'richness', 'right', 'size', 'speak', 'speakHeader',
        'speakNumeral', 'speakPunctuation', 'speechRate', 'stress',
        'tableLayout', 'textAlign', 'textDecoration', 'textIndent',
        'textShadow', 'textTransform', 'top', 'unicodeBidi', 'verticalAlign',
        'visibility', 'voiceFamily', 'volume', 'whiteSpace', 'widows', 'width',
        'wordSpacing', 'zIndex'
    ]

    # For each possible style property, add a wrapper to emit advice.
    do () ->
        proto = dom.CSSStyleDeclaration.prototype
        cssAttrs.forEach (attr) ->
            proto.__defineSetter__ attr, (val) ->
                # cssom seems to use some CSSStyleDeclaration objects
                # internally, so we only want to emit instructions if there
                # is a parent element pointer, meaning this CSSStyleDeclaration
                # belongs to an element.
                if this._parentElement
                    wrapper.emit 'DOMPropertyUpdate',
                        targetID : this._parentElement.__nodeID
                        style : true
                        prop : attr
                        value : val
                return @["_#{attr}"] = val
            proto.__defineGetter__ attr, () ->
                return @["_#{attr}"]

    # TODO:
    # JSDOM uses CSSOM's parse() method to turn text into CSSStyleSheet
    # objects.  We need to replace the current @import rules, which use
    # non-ResourceProxy'd URLs, with ResourceProxy URLs.
    # The ResourceProxy should return the modified CSS sheet instead of
    # fetching from source.
