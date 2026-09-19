require 'xcodeproj'
require 'fileutils'
require 'securerandom'
require 'json'
root = File.expand_path('..', __dir__)
ios = File.join(root, 'ios')
config = JSON.parse(File.read(File.join(root, 'app.json'))).fetch('expo')
version = config.fetch('version')
build_number = config.fetch('ios').fetch('buildNumber', '1')
project = Xcodeproj::Project.open(File.join(ios, 'osu.xcodeproj'))
host = project.targets.find { |t| t.name == 'osu' }
raise 'osu target missing; run expo prebuild first' unless host
native = File.join(ios, 'MimiPrototype')
FileUtils.mkdir_p(native)
Dir[File.join(root, 'native/ios/*')].each { |f| FileUtils.cp(f, native) }
wire = File.join(native, 'MimiWire.swift')
File.write(wire, "enum MimiWire { static let key = \"#{SecureRandom.hex(32)}\" }\n") unless File.exist?(wire)
group = project.main_group.find_subpath('MimiPrototype', true)
group.set_source_tree('<group>'); group.set_path('MimiPrototype')
extension = project.targets.find { |t| t.name == 'MimiBroadcast' } || project.new_target(:app_extension, 'MimiBroadcast', :ios, '18.0')
files = Dir[File.join(native, '*.{swift,m}')]
files.each do |file|
 name = File.basename(file)
 ref = group.files.find { |f| f.path == name } || group.new_file(name)
 targets = name == 'SampleHandler.swift' ? [extension] : ['MimiWire.swift', 'DiagnosticStore.swift'].include?(name) ? [host, extension] : [host]
 targets.each { |t| t.source_build_phase.add_file_reference(ref) unless t.source_build_phase.files_references.include?(ref) }
end
team = host.build_configurations.map { |c| c.build_settings['DEVELOPMENT_TEAM'] }.compact.first
extension.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_NAME'=>'MimiBroadcast','PRODUCT_MODULE_NAME'=>'MimiBroadcast','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.MimiBroadcast','INFOPLIST_FILE'=>'MimiPrototype/Broadcast-Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGN_STYLE'=>'Automatic','SKIP_INSTALL'=>'YES','APPLICATION_EXTENSION_API_ONLY'=>'YES','MARKETING_VERSION'=>version,'CURRENT_PROJECT_VERSION'=>build_number,'SWIFT_OPTIMIZATION_LEVEL'=> c.name == 'Release' ? '-O' : '-Onone'})
 c.build_settings['DEVELOPMENT_TEAM'] = team if team
end
host.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET']='18.0' }
host.add_dependency(extension) unless host.dependencies.any? { |d| d.target == extension }
phase = host.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || host.new_copy_files_build_phase('Embed App Extensions')
phase.dst_subfolder_spec = '13'
unless phase.files_references.include?(extension.product_reference)
 f=phase.add_file_reference(extension.product_reference); f.settings={'ATTRIBUTES'=>['RemoveHeadersOnCopy']}
end
info = {'CFBundleDisplayName'=>'Osu Audio','CFBundleExecutable'=>'$(EXECUTABLE_NAME)','CFBundleIdentifier'=>'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion'=>'6.0','CFBundleName'=>'$(PRODUCT_NAME)','CFBundlePackageType'=>'XPC!','CFBundleShortVersionString'=>version,'CFBundleVersion'=>build_number,'NSExtension'=>{'NSExtensionPointIdentifier'=>'com.apple.broadcast-services-upload','NSExtensionPrincipalClass'=>'$(PRODUCT_MODULE_NAME).SampleHandler','RPBroadcastProcessMode'=>'RPBroadcastProcessModeSampleBuffer'}}
Xcodeproj::Plist.write_to_path(info, File.join(native,'Broadcast-Info.plist'))
info_path = File.join(ios,'osu/Info.plist')
p = Xcodeproj::Plist.read_from_path(info_path)
p['CFBundleDisplayName']='Osu'
p['CFBundleVersion']=build_number
p['NSSpeechRecognitionUsageDescription']='将你主动共享的 App 声音转成本地字幕；不上传音频。'
p['UIBackgroundModes'] = ((p['UIBackgroundModes'] || []) + ['audio']).uniq
Xcodeproj::Plist.write_to_path(p,info_path)
project.save
puts 'Configured Osu host, broadcast extension, and local-only transport.'
