FS        = require('fs')
Assert    = require('assert')
Fork      = require('child_process').fork
Framework = require('../framework')
Nomnom    = require('nomnom')

Opts = Nomnom
    .option 'app',
        default: 'benchmark'
        help: 'Which app to run.'
    .option 'numClients',
        full: 'num-clients'
        required: true
        help: 'The number of clients to create.'
    .option 'type',
        required: true
        help: 'Which benchmark to run: "client" to benchmark additional client costs, "browser" to benchmark additional browser costs.'

Opts = Opts.parse()

serverArgs = ['--compression=false',
              '--debug',
              '--resource-proxy=false',
              '--disable-logging']

if Opts.app == 'chat2'
    serverArgs.push('examples/chat2/app.js')
    serverArgs.unshift('--knockout')
else
    serverArgs.push('examples/benchmark-app/app.js')

server = Framework.createServer
    nodeArgs: ['--expose_gc']
    serverArgs: serverArgs

server.once 'ready', () ->
    server.send({type: 'gc'})
    server.send({type: 'memory'})
    server.once 'message', (msg) ->
        # Results holds the memory usage for a given number of browsers.
        results = [msg.data.heapUsed / 1024]
        console.log("0: #{msg.data.heapUsed / 1024}")
        server.send({type: 'memory'})
        sharedBrowser = (Opts.type == 'client')
        
        Framework.spawnClientsInProcess
            numClients: Opts.numClients
            sharedBrowser: if Opts.type == 'client' then true else false
            clientCallback: (client, cb) ->
                server.send({type: 'gc'})
                server.send({type: 'memory'})
                server.once 'message', (msg) ->
                    Assert.equal(msg.type, 'memory')
                    results[client.id] = msg.data.heapUsed / 1024
                    console.log("#{client.id}: #{ msg.data.heapUsed / 1024}")
                    cb()
            doneCallback: () ->
                prefix = if Opts.type == 'client'
                    'client-mem'
                else
                    'browser-mem'
                outfile = FS.createWriteStream("../results/#{prefix}.dat")
                for result, i in results
                    outfile.write("#{i}\t#{result}\n")
                outfile.end()
                Framework.gnuPlot "#{prefix}.p", () ->
                    server.stop()
                    process.exit(0)