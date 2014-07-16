child_process = require 'child_process'
fs = require 'fs'
qs = require 'querystring'
_ = require 'underscore'

BuildView = require './build-view'

module.exports =
  configDefaults:
    environment: "",
    arguments: ""

  activate: (state) ->
    # Manually append /usr/local/bin as it may not be set on some systems,
    # and it's common to have node installed here. Keep it at end so it won't
    # accidentially override any other node installation
    process.env.PATH += ':/usr/local/bin'

    @root = atom.project.getPath()
    @buildView = new BuildView()
    atom.workspaceView.command "build:trigger", => @build()
    atom.workspaceView.command "build:stop", => @stop()

  deactivate: ->
    @child.kill('SIGKILL') if @child

  buildCommand: ->
    if fs.existsSync @root + './atom-build.json'
      realAtomBuild = fs.realpathSync @root + '/.atom-build.json'
      delete require.cache[realAtomBuild]
      build = require realAtomBuild
      [exec, env, args] = [ build.cmd, build.env, build.args ]

    if !exec && fs.existsSync @root + '/package.json'
      realPackage = fs.realpathSync @root + '/package.json'
      delete require.cache[realPackage]
      pkg = require realPackage
      exec = 'apm' if pkg.engines?.atom
      exec = 'npm' if pkg.engines?.node
      args = [ '--color=always', 'install' ]

    if !exec && fs.existsSync @root + '/Gruntfile.js'
      if fs.existsSync @root + '/node_modules/.bin/grunt'
        # if grunt is installed locally, prefer this
        exec = @root + '/node_modules/.bin/grunt'
      else
        # else use global installation
        exec = 'grunt'

    if !exec && fs.existsSync @root + '/Makefile'
      exec = 'make'

    return {
      exec: exec,
      env: env || {},
      args: args || []
    }

  startNewBuild: ->
    cmd = @buildCommand()
    return if !cmd.exec

    cargs = (atom.config.get('build.arguments').split(' ')).filter((e) -> '' != e)
    env = _.extend(process.env, cmd.env, (qs.parse (atom.config.get 'build.environment'), ' '))
    args = cmd.args.concat(cargs)

    @child = child_process.spawn('/bin/sh', [ '-c', [cmd.exec].concat(args).join(' ') ], { cwd : @root, env: env })
    @child.stdout.on 'data', @buildView.append
    @child.stderr.on 'data', @buildView.append
    @child.on 'error', (err) =>
      @buildView.append 'Unable to execute: ' + cmd.exec
      @buildView.append '`cmd` cannot contain space. Use `args` for arguments.' if /\s/.test(cmd.exec)

    @child.on 'close', (exitCode) =>
      @buildView.buildFinished(0 == exitCode)
      @finishedTimer = (setTimeout (=> @buildView.detach()), 1000) if (0 == exitCode)
      @child = null

    @buildView.buildStarted()
    @buildView.append 'Executing: ' + cmd.exec + [' '].concat(args).join(' ')

  abort: (cb) ->
    @child.removeAllListeners 'close'
    @child.on 'close', =>
      @child = null
      cb() if cb
    @child.kill()

  build: ->
    clearTimeout @finishedTimer
    if @child then @abort(=> @startNewBuild()) else @startNewBuild()

  stop: ->
    if @child
      @abort()
      @buildView.buildAborted()
    else
      @buildView.reset()
