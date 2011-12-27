FS   = require('fs')
Path = require('path')

# TODO: cache nodes after they've been created once.
class Page
    constructor : (options) ->
        {@id, @html, @src, @container} = options

    load : () ->
        div = @container._ownerDocument.createElement('div')
        div.innerHTML = @html
        while @container.childNodes.length
            @container.removeChild(@container.childNodes[0])
        while div.childNodes.length
            @container.appendChild(div.removeChild(div.childNodes[0]))

class WrappedBrowser
    constructor : (parent, browser) ->
        @launch = () ->
            parent.window.open("/browsers/#{browser.id}/index.html")
        @id = browser.id

class InBrowserAPI
    constructor : (window, shared, local) ->
        @window = window
        @shared = shared
        @local  = new local()
    
    @Model : require('./model')

    # This should load the browser in a target iframe.
    embed : (browser) ->

    currentBrowser : () ->
        # TODO: this gives the window access to the whole Browser
        #       implementation, which we really don't want.
        return @window.__browser__

    # TODO: apps need to be objects...passing a url to an app isn't robust.
    #       at worst, we should be passing a string app name.
    createBrowser : (params) ->
        # The global BrowserManager
        manager = global.browsers
        browser = null
        if params.app
            browser = manager.create
                id : params.id
                app : params.app
        else if params.url
            browser = manager.create
                id : params.id
                url : params.url
        else
            throw new Error("Must specify an app or url for browser creation")
        return new WrappedBrowser(@window.__browser__, browser)

    initPages : (elem, callback) ->
        console.log("Inside initPages")
        if !elem?
            throw new Error("Invalid element id passed to loadPages")
        pages = {}
        pendingPages = 0
        # TODO: break this up...DFS w/ callback, string parsing in its own func.
        # TODO: put a DFS in a shared/utils.coffee file.
        dfs = (node) =>
            docPath = node.ownerDocument.location.pathname
            if docPath[0] == '/'
                docPath = docPath.substring(1)
            console.log("docPath: #{docPath}")
            basePath = Path.dirname(Path.resolve(process.cwd(), docPath))
            console.log("basePath: #{basePath}")
            pagePath = null
            if node.nodeType != node.ELEMENT_NODE
                return
            attr = node.getAttribute('data-page')
            if attr? && attr != ''
                console.log("Found an attr")
                page = {container : elem}
                info = attr.split(',')
                for piece in info
                    piece = piece.trim()
                    [key, val] = piece.split(':')
                    val = val.trim()
                    page[key] = val
                if !page['id']
                    throw new Error("Must supply an id for data-page.")
                if !page['src']
                    throw new Error("Must supply a src for data-page.")
                pendingPages++
                pagePath = Path.resolve(basePath, page['src'])
                console.log("Loading page from: #{pagePath}")
                FS.readFile pagePath, 'utf8', (err, data) ->
                    if err
                        console.log(err)
                        console.log(err.stack)
                        throw err
                    page['html'] = data
                    pages[page['id']] = new Page(page)
                    if --pendingPages == 0
                        if callback then callback(pages)
            else
                for child in node.childNodes
                    dfs(child)
        dfs(elem)

module.exports = InBrowserAPI
