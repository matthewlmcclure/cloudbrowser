Path        = require('path')
Hat         = require('hat')
{dfs}       = require('../shared/utils')
{ko}        = require('./ko')
DataPage    = require('./data_page')
Application = require('../server/application')

# This is intended to be the "Browser" object that applications interact with.
# # TODO: this exposes the parent browser in its entirety, need to only expose it as Wrapped (embed this in EmbedAPI)
class WrappedBrowser
    # TODO: WrappedBrowser#embed(iframe) - launch into iframe
    constructor : (parent, browser) ->
        @launch = () ->
            parent.window.open("/browsers/#{browser.id}/index.html")
        @id = browser.id

module.exports = EmbedAPI = (browser) ->
    window = browser.window
    app = browser.app

    window.vt = {}

    window.vt.Model = require('./model')

    window.vt.createBrowser = (app, id) ->
        if !id? then id = Hat()
        b = global.browsers.create(app, id)
        return new WrappedBrowser(browser, b)

    window.vt.createApplication = (opts) ->
        # Passed an Application constructor options object.
        if typeof opts == 'object'
            app = new Application(opts)
            app.mount(global.server)
            return app
        # Passed a path to an app directory.
        if typeof opts == 'string'
            configPath = Path.resolve(process.cwd(), opts)
            appOpts = require(configPath).app
            app = new Application(appOpts)
            app.mount(global.server)
            return app
        throw new Error("Invalid parameter: #{opts}")

    window.vt.currentBrowser = () ->
        return new WrappedBrowser(null, browser)

    window.vt.initPages = (elem, callback) ->
        if !elem?
            throw new Error("Invalid element id passed to loadPages")

        # Setting pages.activePage(string) changes which page is displayed
        # in the parent elem.
        pages = {activePage : ko.observable('')}

        # Filter out non-nodes
        filter = (node) ->
            return node.nodeType == 1 # ELEMENT_NODE

        pendingPages = 0
        dfs elem, filter, (node) ->
            attr = node.getAttribute('data-page')
            if attr && attr != ''
                page = new DataPage(node, attr)
                pages[page.id] = page
                pendingPages++
                page.once 'load', () ->
                    callback(pages) if (--pendingPages == 0) and callback?

        elem._ownerDocument._parentWindow.ko.applyBindings(pages, elem)