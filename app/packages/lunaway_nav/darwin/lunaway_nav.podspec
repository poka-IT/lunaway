# For a build with Swift Package Manager turned off; Package.swift is the
# usual way in.
Pod::Spec.new do |s|
  s.name             = 'lunaway_nav'
  s.version          = '0.1.0'
  s.summary          = 'Spoken instructions of the Lunaway guidance.'
  s.description      = 'The platform speech engine, for the turn-by-turn guidance of the Lunaway app.'
  s.homepage         = 'https://lunaway.net'
  s.license          = { :type => 'AGPL-3.0-or-later' }
  s.author           = { 'Lunaway' => 'https://lunaway.net' }
  s.source           = { :path => '.' }
  s.source_files = 'lunaway_nav/Sources/lunaway_nav/**/*.swift'
  s.resource_bundles = { 'lunaway_nav_privacy' => ['lunaway_nav/Sources/lunaway_nav/PrivacyInfo.xcprivacy'] }
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
