require 'xcodeproj'
require 'fileutils'
root = File.expand_path('..', __dir__)
dir = File.join(root, 'ios', 'SimulatorHarness')
FileUtils.mkdir_p(dir)
p = Xcodeproj::Project.new(File.join(dir, 'MimiSimulator.xcodeproj'))
t = p.new_target(:application, 'MimiSimulator', :ios, '18.0')
g = p.main_group.new_group('Sources')
sources = Dir[File.join(root, 'native/ios/*.swift')].reject { |f| ['SampleHandler.swift', 'MimiPrototype.swift'].include?(File.basename(f)) }
sources += [File.join(root, 'native/tests/SimulatorHarness.swift'), File.join(root, 'ios/MimiPrototype/MimiWire.swift')]
sources.each { |f| t.source_build_phase.add_file_reference(g.new_file(f)) }
t.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_NAME'=>'MimiSimulator','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.SimulatorTests','INFOPLIST_FILE'=>'Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','TARGETED_DEVICE_FAMILY'=>'1,2','CODE_SIGNING_ALLOWED'=>'NO'})
end
Xcodeproj::Plist.write_to_path({'CFBundleDisplayName'=>'Mimi Simulator','CFBundleExecutable'=>'$(EXECUTABLE_NAME)','CFBundleIdentifier'=>'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName'=>'$(PRODUCT_NAME)','CFBundlePackageType'=>'APPL','CFBundleShortVersionString'=>'1.0','CFBundleVersion'=>'1','LSRequiresIPhoneOS'=>true,'UILaunchScreen'=>{},'UIBackgroundModes'=>['audio'],'NSSpeechRecognitionUsageDescription'=>'Test local subtitle recognition.','UISupportedInterfaceOrientations'=>['UIInterfaceOrientationPortrait']}, File.join(dir, 'Info.plist'))
p.save
scheme = Xcodeproj::XCScheme.new; scheme.add_build_target(t); scheme.set_launch_target(t); scheme.save_as(p.path, 'MimiSimulator', true)
puts 'Configured isolated simulator harness using production native code.'
