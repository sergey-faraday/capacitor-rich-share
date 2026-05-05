require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapacitorRichShare'
  s.version = package['version']
  s.summary = 'Native-quality Capacitor sharing: image+text sheet, Save to Photos/Gallery, deep-links to IG/FB/Snap/TikTok/WA/TG/X/LinkedIn.'
  s.description = package['description']
  s.license = package['license']
  s.homepage = 'https://github.com/sergey-faraday/capacitor-rich-share'
  s.author = package['author']
  s.source = { :git => 'https://github.com/sergey-faraday/capacitor-rich-share.git', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.9'
  s.frameworks = 'UIKit', 'Photos'
end
