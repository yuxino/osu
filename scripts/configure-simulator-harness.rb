require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
dir = File.join(root, 'ios', 'SimulatorHarness')
FileUtils.mkdir_p(dir)
p = Xcodeproj::Project.new(File.join(dir, 'MimiSimulator.xcodeproj'))
t = p.new_target(:application, 'MimiSimulator', :ios, '18.0')
g = p.main_group.new_group('Sources')
sources = Dir[File.join(root, 'native/ios/*.swift')].reject { |f| ['SampleHandler.swift', 'MimiPrototype.swift'].include?(File.basename(f)) }
sources += [File.join(root, 'native/tests/CloudFixture.swift'), File.join(root, 'native/tests/SimulatorHarness.swift'), File.join(root, 'native/tests/LyricsClipExporter.swift'), File.join(root, 'ios/MimiPrototype/MimiWire.swift')]
sources << File.join(root, 'native/tests/SessionFinishFixture.swift')
sources << File.join(root, 'native/tests/LyricsRenderFixture.swift')
sources << File.join(root, 'native/tests/StreamEnduranceFixture.swift')
sources << File.join(root, 'native/tests/MotionFixture.swift')
sources << File.join(root, 'native/tests/InteractionFixture.swift')
sources << File.join(root, 'native/tests/IslandFixture.swift')
sources.each { |f| t.source_build_phase.add_file_reference(g.new_file(f)) }
t.resources_build_phase.add_file_reference(g.new_file(File.join(root, 'assets/brand/mimi-maid-v1.png')))
t.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_NAME'=>'MimiSimulator','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.SimulatorTests','INFOPLIST_FILE'=>'Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGNING_ALLOWED'=>'YES','CODE_SIGN_IDENTITY'=>'-'})
end
Xcodeproj::Plist.write_to_path({'CFBundleDisplayName'=>'Osu Tests','CFBundleExecutable'=>'$(EXECUTABLE_NAME)','CFBundleIdentifier'=>'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName'=>'$(PRODUCT_NAME)','CFBundlePackageType'=>'APPL','CFBundleShortVersionString'=>'1.0','CFBundleVersion'=>'1','LSRequiresIPhoneOS'=>true,'UILaunchScreen'=>{},'UIBackgroundModes'=>['audio'],'NSSpeechRecognitionUsageDescription'=>'Test local subtitle recognition.','UISupportedInterfaceOrientations'=>['UIInterfaceOrientationPortrait']}, File.join(dir, 'Info.plist'))
widget = p.new_target(:app_extension, 'IslandWidget', :ios, '18.0')
[File.join(root, 'native/ios/SubtitleActivityAttributes.swift'), File.join(root, 'native/widget/SubtitleWidget.swift')].each { |f| widget.source_build_phase.add_file_reference(g.new_file(f)) }
widget.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_NAME'=>'IslandWidget','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.SimulatorTests.IslandWidget','INFOPLIST_FILE'=>'Widget-Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','SKIP_INSTALL'=>'YES','APPLICATION_EXTENSION_API_ONLY'=>'YES','CODE_SIGN_IDENTITY'=>'-'})
end
Xcodeproj::Plist.write_to_path({'CFBundleDisplayName'=>'Osu Test Subtitles','CFBundleExecutable'=>'$(EXECUTABLE_NAME)','CFBundleIdentifier'=>'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName'=>'$(PRODUCT_NAME)','CFBundlePackageType'=>'XPC!','CFBundleShortVersionString'=>'1.0','CFBundleVersion'=>'1','NSExtension'=>{'NSExtensionPointIdentifier'=>'com.apple.widgetkit-extension'}}, File.join(dir, 'Widget-Info.plist'))
t.add_dependency(widget)
phase = t.new_copy_files_build_phase('Embed App Extensions'); phase.dst_subfolder_spec = '13'
phase.add_file_reference(widget.product_reference).settings = {'ATTRIBUTES'=>['RemoveHeadersOnCopy']}
info_path = File.join(dir, 'Info.plist'); info = Xcodeproj::Plist.read_from_path(info_path); info['NSSupportsLiveActivities'] = true; Xcodeproj::Plist.write_to_path(info, info_path)
probe = p.new_target(:application, 'IslandProcessProbe', :ios, '18.0')
# CloudFixture contains UI fixtures as well as its in-memory socket; use the same
# native source set as the harness so those fixture references resolve.
probe_sources = sources.reject { |f| File.basename(f) == 'SimulatorHarness.swift' }
probe_sources += [File.join(root, 'native/tests/IslandProcessProbe.swift')]
probe_sources.each { |f| probe.source_build_phase.add_file_reference(g.new_file(f)) }
probe.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_NAME'=>'IslandProcessProbe','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.SimulatorTests.ProcessProbe','INFOPLIST_FILE'=>'Probe-Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGN_IDENTITY'=>'-'})
end
probe_info = Xcodeproj::Plist.read_from_path(info_path)
probe_info['CFBundleDisplayName'] = 'Osu Process Probe'
Xcodeproj::Plist.write_to_path(probe_info, File.join(dir, 'Probe-Info.plist'))
p.save
scheme = Xcodeproj::XCScheme.new; scheme.add_build_target(t); scheme.add_build_target(probe); scheme.set_launch_target(t); scheme.save_as(p.path, 'MimiSimulator', true)
puts 'Configured isolated simulator harness using production native code.'
