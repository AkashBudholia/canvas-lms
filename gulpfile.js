const gulp = require('gulp')
const gulpPlugins = require('gulp-load-plugins')()
const merge = require('merge-stream')
const rename = require('gulp-rename')

const DIST = 'public/dist'

const STUFF_TO_REV = [
  'public/fonts/**/*.{eot,otf,svg,ttf,woff,woff2}',
  'public/images/**/*',



  // These files have links in their css to images from their own dir
  'public/javascripts/vendor/slickgrid/images/*',

  // Include *everything* from plugins
  // so we don't have to worry about their internals
  // TODO: do we need these if we are all-webpack?
  // exclude .js here
  'public/plugins/**/*.*',
]

gulp.task('rev', () => {
  const timezonefilesToIgnore = [
    'loaded.js',
    'locales.js',
    'rfc822.js',
    'synopsis.js',
    'zones.js',
    'de_DE.js',
    'fr_FR.js',
    'fr_CA.js',
    'he_IL.js',
    'pl_PL.js',
    '**/index.js',
  ].map(f => `!./node_modules/timezone/${f}`)

  const timezoneFileGlobs = ['./node_modules/timezone/**/*.js'].concat(timezonefilesToIgnore)
  const timezonesStream = gulp
    .src(timezoneFileGlobs, {base: './node_modules'})
    .pipe(gulpTimezonePlugin())

  const customTimezoneStream = gulp
    .src('./public/javascripts/custom_timezone_locales/*.js')
    .pipe(rename(path => path.dirname = '/timezone'))
    .pipe(gulpTimezonePlugin())

  const fontfaceObserverStream = gulp
    .src('node_modules/fontfaceobserver/fontfaceobserver.standalone.js')
    .pipe(gulpPlugins.rename('lato-fontfaceobserver.js'))
    .pipe(gulpPlugins.insert.wrap(`
      // Optimization for Repeat Views
      if (sessionStorage.latoFontLoaded) {
        document.documentElement.classList.remove('lato-font-not-loaded-yet')
      } else {
      `
      ,
      `
        new FontFaceObserver('LatoWeb').load().then(function () {
          sessionStorage.latoFontLoaded = true;
          document.documentElement.classList.remove('lato-font-not-loaded-yet')
        }, console.log.bind(console, 'Failed to load Lato font'));
      }
      `
    ))

  return makeIE11Polyfill().then((IE11PolyfillCode) => {

    let stream = merge(
      timezonesStream,
      customTimezoneStream,
      fontfaceObserverStream,
      gulpPlugins.file('ie11-polyfill.js', IE11PolyfillCode, { src: true }),
      gulp.src(STUFF_TO_REV, {
        base: 'public', // tell it to use the 'public' folder as the base of all paths
        follow: true // follow symlinks, so it picks up on images inside plugins and stuff
      }),
      gulp.src([
        // on the mobile login screen, we don't load any of our webpack js bundles. but if they
        // have a custom js file, we do load a raw copy of jquery for their custom js to use.
        // See `include_account_js` in mobile_auth.html.erb
        'node_modules/jquery/jquery.js',

        'node_modules/tinymce/skins/lightgray/**/*',
      ], {
        base: '.'
      })
    ).pipe(gulpPlugins.rev())

    if (process.env.NODE_ENV === 'production' || process.env.RAILS_ENV === 'production') {
      const jsFilter = gulpPlugins.filter('**/*.js', {restore: true});
      stream = stream.pipe(jsFilter)
        .pipe(gulpPlugins.sourcemaps.init())
        .pipe(gulpPlugins.uglify())
        .pipe(gulpPlugins.sourcemaps.write('./maps'))
        .pipe(jsFilter.restore)
    }

    return stream
      .pipe(gulp.dest(DIST))
      .pipe(gulpPlugins.rev.manifest())
      .pipe(gulp.dest(DIST))
  })
})

gulp.task('watch', () => gulp.watch(STUFF_TO_REV, ['rev']))

gulp.task('default', ['rev', 'watch'])


function gulpTimezonePlugin () {
  const through = require('through2')

  const wrapTimezone = (code, timezoneName) =>
`// this was autogenerated by gulpTimezonePlugin from the timezone source in node_modules
(window.__PRELOADED_TIMEZONE_DATA__ || (window.__PRELOADED_TIMEZONE_DATA__ = {}))['${timezoneName}'] ${code.toString().replace('module.exports', '')}
`

  return through.obj((file, encoding, callback) => {
    if (file.isNull()) return callback(null, file)
    if (file.isBuffer()) {
      const timezoneName = file.path
        .replace(/.*\/timezone\//, '')
        .replace(/\.js$/, '')
      file.contents = new Buffer(wrapTimezone(file.contents, timezoneName))
      return callback(null, file)
    }
  })
}


function makeIE11Polyfill () {
  const coreJsBuilder = require('core-js-builder')

  const FEATURES_TO_POLYFILL = [
    'es6.promise',
    'es6.object.assign',
    'es6.object.is',
    'es7.object.values',
    'es7.object.entries',
    'es6.array',
    'es7.array.includes',
    'es6.function',
    'es6.string.ends-with',
    'es6.string.includes',
    'es6.string.starts-with',
    'es6.symbol',
    'es6.map'
  ]

  return coreJsBuilder({
    modules: FEATURES_TO_POLYFILL,
    library: false,
    umd: false
  }).then(code =>
`/*
THIS FILE WAS AUTOGENERATED BY gulp in makeIE11Polyfill to polyfill the following features:
${FEATURES_TO_POLYFILL}
*/
${code}`
  )
}
