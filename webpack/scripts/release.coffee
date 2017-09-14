require('dotenv').config()
require('../circle')

pkg = require('../../package.json')
version = require('../version')
path = require('path')

Bluebird = require('bluebird')
github = require('./github')

PRERELEASE = true # TODO: remove after release

process.exit() if process.env.CI_PULL_REQUEST

build_root = path.join(__dirname, '../../')

if process.env.CIRCLE_TAG
  if "v#{pkg.version}" != process.env.CIRCLE_TAG
    console.log("Building tag #{process.env.CIRCLE_TAG}, but package version is #{pkg.version}")
    process.exit(1)
  if process.env.CIRCLE_BRANCH != 'master'
    console.log("Building tag #{process.env.CIRCLE_TAG}, but branch is #{process.env.CIRCLE_BRANCH}")
    process.exit(1)

if process.env.CIRCLE_BRANCH.startsWith('@')
  console.log("Not releasing #{process.env.CIRCLE_BRANCH}")
  process.exit(0)

announce = Bluebird.coroutine((issue)->
  if process.env.CIRCLE_TAG
    build = "#{if PRERELEASE then 'pre-' else ''}release #{process.env.CIRCLE_TAG}"
    reason = ''
  else
    build = "test build #{process.env.CIRCLE_BUILD_NUM}"
    reason = ", apparently because #{process.env.CIRCLE_COMMIT_MSG}"

  msg = ":robot: bleep bloop; this is your friendly neighborhood build bot announcing [#{build}](https://github.com/retorquere/zotero-better-bibtex/releases/download/builds/zotero-better-bibtex-#{version}.xpi)#{reason}."
  console.log(msg)

  return
  try
    yield github({
      uri: "/issues/#{issue}/comments"
      method: 'POST'
      body: { body: msg }
    })
  return
)

do Bluebird.coroutine(->
  console.log('finding releases')
  release = {
    static: 'static-files',
    current: "v#{pkg.version}",
    builds: 'builds',
  }

  for id, tag of release
    release[id] = null
    try
      release[id] = yield github("/releases/tags/#{tag}")
      console.log("#{tag} found")

  xpi = "zotero-better-bibtex-#{version}.xpi"

  if process.env.CIRCLE_TAG
    if release.current
      console.log("release #{process.env.CIRCLE_TAG} exists, bailing")
      process.exit(1)

    if !release.static
      console.log("release 'static-files' does not exists, bailing")
      process.exit(1)

    update_rdf = release.static.assets?.find((asset) -> asset.name == 'update.rdf')
    yield github({ method: 'DELETE', uri: "/releases/assets/#{update_rdf.id}" }) if update_rdf

    # create release.current
    release.current = yield github({
      uri: '/releases'
      method: 'POST'
      body: {
        tag_name: process.env.CIRCLE_TAG
        prerelease: !!PRERELEASE
      }
    })

    console.log("uploading #{xpi} to #{release.current.name}")
    yield github.upload({
      release: release.current,
      name: xpi,
      path: path.resolve(__dirname, path.join(build_root, "xpi/#{xpi}"))
      content_type: 'application/x-xpinstall'
    })

    yield github.upload({
      release: release.static,
      name: 'update.rdf',
      path: path.resolve(__dirname, '../../gen/update.rdf')
      content_type: 'application/rdf+xml'
    })

    # yield release.builds.upload(xpi, 'application/x-xpinstall', fs.readFileSync(path.join(build_root, "xpi/#{xpi}")))

    yield announce(555) # TODO: remove after release

  else
    if !release.builds
      console.log('no release for builds')
      process.exit(1)

    release.builds.assets ||= []
    release.builds.assets.sort((a, b) -> (new Date(b.created_at)).getTime() - (new Date(a.created_at)).getTime())
    for asset, i in release.builds.assets
      continue if i < 5 && asset.name != xpi
      yield github({ method: 'DELETE', uri: "/releases/assets/#{asset.id}" })

    console.log("uploading #{xpi} to builds")
    yield github.upload({
      release: release.builds,
      name: xpi,
      path: path.resolve(__dirname, path.join(build_root, "xpi/#{xpi}"))
      content_type: 'application/x-xpinstall'
    })

    branch = process.env.CIRCLE_BRANCH
    if process.env.NIGHTLY == 'true'
      issue = null
    else if branch.match(/^[0-9]+$/)
      issue = branch
    else if branch == 'master' # TODO: remove after release
      issue = '555'
    else
      issue = null

    yield announce(issue) if issue

  return
)
